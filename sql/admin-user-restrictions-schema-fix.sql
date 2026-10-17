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
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_type text := lower(btrim(coalesce(p_restriction_type,'')));
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if not coalesce(public.mzad_is_admin(),false) then raise exception 'ADMIN_REQUIRED'; end if;
  if p_user_id is null then raise exception 'USER_REQUIRED'; end if;
  if p_user_id=auth.uid() then raise exception 'CANNOT_RESTRICT_SELF'; end if;
  if v_type not in ('all','bid','sell','buy','deposit') then raise exception 'INVALID_RESTRICTION_TYPE'; end if;
  if p_expires_at is not null and p_expires_at<=now() then raise exception 'INVALID_EXPIRY'; end if;

  update public.mzad_user_restrictions
     set is_active=false, updated_at=now()
   where user_id=p_user_id and restriction_type=v_type and is_active is true;

  insert into public.mzad_user_restrictions
    (user_id,restriction_type,reason,notes,starts_at,expires_at,is_active,created_by,created_at,updated_at)
  values
    (p_user_id,v_type,nullif(btrim(coalesce(p_reason,'')),''),
     nullif(btrim(coalesce(p_notes,'')),''),now(),p_expires_at,true,auth.uid(),now(),now())
  returning id into v_id;

  insert into public.mzad_admin_audit(admin_id,action,target,details)
  values(auth.uid(),'user_restrict',p_user_id::text,
    jsonb_build_object('restriction_type',v_type,'restriction_id',v_id,
      'expires_at',p_expires_at,'reason',p_reason,'notes',p_notes));

  return jsonb_build_object('ok',true,'id',v_id,'restriction_type',v_type,'expires_at',p_expires_at);
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
