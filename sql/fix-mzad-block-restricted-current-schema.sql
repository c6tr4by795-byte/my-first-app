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
