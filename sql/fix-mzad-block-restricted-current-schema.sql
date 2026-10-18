-- MZAD PHONE: fix restriction trigger to use the current schema.
-- Safe scope: replaces only the trigger function; does not modify rows, tables, or triggers.
create or replace function public.mzad_block_restricted()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid;
  v_kind text := lower(coalesce(tg_argv[0], ''));
  v_blocked boolean := false;
begin
  v_user_id := case v_kind
    when 'bid' then nullif(to_jsonb(new) ->> 'bidder_user_id', '')::uuid
    when 'deposit' then nullif(to_jsonb(new) ->> 'user_id', '')::uuid
    when 'sell' then nullif(to_jsonb(new) ->> 'seller_user_id', '')::uuid
    else null
  end;

  if v_user_id is null then
    return new;
  end if;

  if v_kind not in ('bid', 'deposit', 'sell') then
    raise exception 'INVALID_RESTRICTION_OPERATION';
  end if;

  select exists (
    select 1
      from public.mzad_user_restrictions r
     where r.user_id = v_user_id
       and r.is_active is true
       and r.starts_at <= now()
       and (r.expires_at is null or r.expires_at > now())
       and r.restriction_type in (v_kind, 'all')
  )
  into v_blocked;

  if v_blocked then
    if v_kind = 'bid' then
      raise exception 'USER_BID_RESTRICTED';
    elsif v_kind = 'deposit' then
      raise exception 'USER_DEPOSIT_RESTRICTED';
    elsif v_kind = 'sell' then
      raise exception 'USER_SELL_RESTRICTED';
    end if;
  end if;

  return new;
end;
$function$;

-- Keep the public status RPC aligned with the current restriction schema.
-- This changes no tables or rows; it replaces only the status function.
create or replace function public.mzad_public_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $status$
declare
  n public.mzad_platform_notice;
  me jsonb := null;
  uid uuid := auth.uid();
  v_banned boolean := false;
  v_no_bid boolean := false;
  v_no_sell boolean := false;
  v_no_deposit boolean := false;
  v_reason text := null;
  v_until timestamptz := null;
  v_has_permanent boolean := false;
begin
  select * into n
    from public.mzad_platform_notice
   where id = 1;

  if uid is not null then
    select
      coalesce(bool_or(r.restriction_type = 'all'), false),
      coalesce(bool_or(r.restriction_type in ('bid', 'all')), false),
      coalesce(bool_or(r.restriction_type in ('sell', 'all')), false),
      coalesce(bool_or(r.restriction_type in ('deposit', 'all')), false),
      coalesce(bool_or(r.expires_at is null), false),
      max(r.expires_at)
    into v_banned, v_no_bid, v_no_sell, v_no_deposit, v_has_permanent, v_until
    from public.mzad_user_restrictions r
    where r.user_id = uid
      and r.is_active is true
      and r.starts_at <= now()
      and (r.expires_at is null or r.expires_at > now());

    select r.reason
      into v_reason
      from public.mzad_user_restrictions r
     where r.user_id = uid
       and r.is_active is true
       and r.starts_at <= now()
       and (r.expires_at is null or r.expires_at > now())
       and r.reason is not null
     order by r.created_at desc
     limit 1;

    if v_banned or v_no_bid or v_no_sell or v_no_deposit then
      if v_has_permanent then
        v_until := null;
      end if;
      me := jsonb_build_object(
        'banned', v_banned,
        'no_bid', v_no_bid,
        'no_sell', v_no_sell,
        'no_deposit', v_no_deposit,
        'reason', v_reason,
        'until', v_until
      );
    end if;
  end if;

  return jsonb_build_object(
    'maintenance', jsonb_build_object(
      'on', coalesce(public.mzad_setting_bool('maintenance_mode'), false),
      'style', coalesce(n.style, 'maintenance'),
      'title', n.title,
      'message', n.message,
      'eta_at', n.eta_at,
      'show_phone', coalesce(n.show_phone, true)
    ),
    'announcement', case
      when nullif(btrim(coalesce(n.announcement, '')), '') is not null
       and (n.announcement_until is null or n.announcement_until > now())
      then n.announcement else null end,
    'flags', jsonb_build_object(
      'bidding', public.mzad_setting_bool('bidding_enabled'),
      'auctions', public.mzad_setting_bool('auctions_enabled'),
      'deposits', public.mzad_setting_bool('deposits_enabled'),
      'registration', public.mzad_setting_bool('registration_enabled')
    ),
    'me', me,
    'server_time', now()
  );
end;
$status$;

-- Compatibility RPC used by the existing admin dashboard.
-- Maps its legacy checkbox payload to the current restriction_type table.
create or replace function public.mzad_admin_set_restriction(
  p_user_id uuid,
  p_banned boolean,
  p_no_bid boolean,
  p_no_sell boolean,
  p_no_deposit boolean,
  p_reason text default null,
  p_until timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $restriction$
declare
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_type text;
  v_before jsonb;
  v_after jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not coalesce(public.mzad_is_admin(), false) then
    raise exception 'ADMIN_REQUIRED';
  end if;
  if p_user_id is null then
    raise exception 'USER_REQUIRED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_RESTRICT_SELF';
  end if;
  if p_until is not null and p_until <= now() then
    raise exception 'INVALID_EXPIRY';
  end if;
  if not exists (select 1 from public.mzad_profiles where user_id = p_user_id) then
    raise exception 'USER_NOT_FOUND';
  end if;

  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_before
    from public.mzad_user_restrictions r
   where r.user_id = p_user_id and r.is_active is true;

  -- Replace only the legacy-managed restriction types; keep unrelated 'buy' rows intact.
  update public.mzad_user_restrictions
     set is_active = false, updated_at = now()
   where user_id = p_user_id
     and is_active is true
     and restriction_type in ('all', 'bid', 'sell', 'deposit');

  if coalesce(p_banned, false) then
    insert into public.mzad_user_restrictions
      (user_id, restriction_type, reason, starts_at, expires_at, is_active, created_by)
    values (p_user_id, 'all', v_reason, now(), p_until, true, auth.uid())
    returning jsonb_build_array(to_jsonb(public.mzad_user_restrictions.*)) into v_after;
  else
    for v_type in
      select x.kind
      from (values
        ('bid', coalesce(p_no_bid, false)),
        ('sell', coalesce(p_no_sell, false)),
        ('deposit', coalesce(p_no_deposit, false))
      ) as x(kind, enabled)
      where x.enabled
    loop
      insert into public.mzad_user_restrictions
        (user_id, restriction_type, reason, starts_at, expires_at, is_active, created_by)
      values (p_user_id, v_type, v_reason, now(), p_until, true, auth.uid());
    end loop;

    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
      into v_after
      from public.mzad_user_restrictions r
     where r.user_id = p_user_id and r.is_active is true
       and r.restriction_type in ('all', 'bid', 'sell', 'deposit');
  end if;

  perform public.mzad_write_audit(
    'admin_user_restriction_changed',
    'user',
    p_user_id,
    v_before,
    v_after,
    jsonb_build_object('reason', v_reason, 'expires_at', p_until)
  );

  return jsonb_build_object('ok', true, 'user_id', p_user_id, 'restrictions', v_after);
end;
$restriction$;

revoke all on function public.mzad_admin_set_restriction(uuid, boolean, boolean, boolean, boolean, text, timestamptz) from public, anon;
grant execute on function public.mzad_admin_set_restriction(uuid, boolean, boolean, boolean, boolean, text, timestamptz) to authenticated;
