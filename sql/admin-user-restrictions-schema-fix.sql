-- MZAD PHONE: admin restriction RPCs matching the existing restriction table.
-- Table columns used: user_id, restriction_type, reason, notes, starts_at,
-- expires_at, is_active, created_by, created_at, updated_at.
-- Review and run in Supabase SQL Editor. Existing tables and triggers are preserved.

begin;

create or replace function public.mzad_admin_restrict_user(
  p_user_id uuid,
  p_restriction_type text,
  p_reason text default null,
  p_notes text default null,
  p_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_type text := lower(btrim(coalesce(p_restriction_type,'')));
  v_id uuid;
  v_before jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not coalesce(public.mzad_is_admin(), false) then
    raise exception 'ADMIN_ONLY';
  end if;
  if p_user_id is null then
    raise exception 'USER_REQUIRED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_RESTRICT_SELF';
  end if;
  if v_type not in ('bid','sell','buy','all','deposit') then
    raise exception 'INVALID_RESTRICTION_TYPE';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'INVALID_EXPIRY';
  end if;
  if not exists (
    select 1 from public.mzad_profiles where user_id = p_user_id
  ) then
    raise exception 'USER_NOT_FOUND';
  end if;

  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_before
  from public.mzad_user_restrictions r
  where r.user_id = p_user_id and r.is_active is true;

  update public.mzad_user_restrictions
     set is_active = false, updated_at = now()
   where user_id = p_user_id
     and restriction_type = v_type
     and is_active is true;

  insert into public.mzad_user_restrictions
    (user_id, restriction_type, reason, notes, starts_at, expires_at,
     is_active, created_by)
  values
    (p_user_id, v_type, nullif(btrim(coalesce(p_reason,'')), ''),
     nullif(btrim(coalesce(p_notes,'')), ''), now(), p_expires_at,
     true, auth.uid())
  returning id into v_id;

  perform public.mzad_write_audit(
    'admin_user_restricted',
    'user',
    p_user_id,
    v_before,
    jsonb_build_object(
      'restriction_id', v_id,
      'restriction_type', v_type,
      'reason', p_reason,
      'notes', p_notes,
      'expires_at', p_expires_at
    ),
    '{}'::jsonb
  );

  return v_id;
end;
$function$;

create or replace function public.mzad_admin_unrestrict_user(
  p_user_id uuid,
  p_restriction_type text default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_type text := nullif(lower(btrim(coalesce(p_restriction_type,''))),'');
  v_count integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if not coalesce(public.mzad_is_admin(),false) then raise exception 'ADMIN_REQUIRED'; end if;
  if p_user_id is null then raise exception 'USER_REQUIRED'; end if;
  if v_type is not null and v_type not in ('all','bid','sell','buy','deposit') then raise exception 'INVALID_RESTRICTION_TYPE'; end if;

  update public.mzad_user_restrictions
     set is_active=false, updated_at=now()
   where user_id=p_user_id and is_active is true
     and (v_type is null or restriction_type=v_type);
  get diagnostics v_count = row_count;

  insert into public.mzad_admin_audit(admin_id,action,target,details)
  values(auth.uid(),'user_unrestrict',p_user_id::text,
    jsonb_build_object('restriction_type',v_type,'rows_deactivated',v_count,'reason',p_reason));

  return jsonb_build_object('ok',true,'rows_deactivated',v_count);
end;
$function$;

commit;

-- Note: the trigger function mzad_block_restricted and user listing RPC are not
-- changed in this file. Verify the installed profile schema before modifying them.
