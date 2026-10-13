-- MZAD PHONE: server-side device verification controls
-- Apply in STAGING first. This migration is additive and does not alter page styling.
begin;

create or replace function public.mzad_admin_review_device_verification(
  p_device_id uuid,
  p_decision text,
  p_reason text,
  p_match_json jsonb default '{}'::jsonb
) returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  d public.mzad_devices%rowtype;
  v_duplicate_imei boolean := false;
  v_duplicate_serial boolean := false;
  v_before jsonb;
  v_after jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
begin
  if v_actor is null or not public.mzad_is_admin() then
    raise exception 'ADMIN_REQUIRED';
  end if;
  if p_decision not in ('approved','rejected','needs_changes','under_review') then
    raise exception 'INVALID_VERIFICATION_DECISION';
  end if;
  if jsonb_typeof(coalesce(p_match_json,'{}'::jsonb)) <> 'object' then
    raise exception 'MATCH_CHECKLIST_MUST_BE_OBJECT';
  end if;
  if p_decision in ('rejected','needs_changes') and v_reason is null then
    raise exception 'REASON_REQUIRED';
  end if;

  select * into d from public.mzad_devices where id=p_device_id for update;
  if not found then raise exception 'DEVICE_NOT_FOUND'; end if;

  -- The approval gate must run inside this privileged RPC, not as a UI-only check.
  -- Deploy sql/mzad-verification-approval-gate.sql before this migration.
  if p_decision='approved' then
    perform public.mzad_admin_require_inspection_report(p_device_id);
  end if;

  if nullif(btrim(coalesce(d.imei,'')),'') is not null then
    select exists(select 1 from public.mzad_devices x
      where x.id<>d.id and x.imei=btrim(d.imei)
        and x.verification_status in ('pending','under_review','approved','needs_changes'))
      into v_duplicate_imei;
  end if;
  if nullif(btrim(coalesce(d.serial_number,'')),'') is not null then
    select exists(select 1 from public.mzad_devices x
      where x.id<>d.id and x.serial_number=btrim(d.serial_number)
        and x.verification_status in ('pending','under_review','approved','needs_changes'))
      into v_duplicate_serial;
  end if;

  if p_decision='approved' and (v_duplicate_imei or v_duplicate_serial) then
    raise exception 'DUPLICATE_DEVICE_IDENTIFIER_REQUIRES_MANUAL_REVIEW';
  end if;
  if p_decision='approved' and coalesce(p_match_json,'{}'::jsonb) = '{}'::jsonb then
    raise exception 'MATCH_CHECKLIST_REQUIRED';
  end if;

  v_before := jsonb_build_object(
    'verification_status',d.verification_status,
    'verified_by',d.verified_by,
    'verified_at',d.verified_at
  );
  update public.mzad_devices
    set verification_status=p_decision,
        verified_by=case when p_decision='approved' then v_actor else null end,
        verified_at=case when p_decision='approved' then now() else null end,
        updated_at=now()
    where id=d.id;

  insert into public.mzad_device_events(device_id,event_type,actor_user_id,payload_json)
  values(d.id,'verification_reviewed',v_actor,jsonb_build_object(
    'decision',p_decision,
    'reason',v_reason,
    'match_checklist',coalesce(p_match_json,'{}'::jsonb),
    'duplicate_imei_detected',v_duplicate_imei,
    'duplicate_serial_detected',v_duplicate_serial
  ));

  v_after := jsonb_build_object(
    'verification_status',p_decision,
    'verified_by',case when p_decision='approved' then v_actor else null end,
    'verified_at',case when p_decision='approved' then now() else null end,
    'reason',v_reason,
    'match_checklist',coalesce(p_match_json,'{}'::jsonb),
    'duplicate_imei_detected',v_duplicate_imei,
    'duplicate_serial_detected',v_duplicate_serial
  );
  insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
  values(v_actor,'device_verification_reviewed','device',d.id::text,v_before,v_after);

  return true;
end;
$$;

revoke all on function public.mzad_admin_review_device_verification(uuid,text,text,jsonb) from public, anon;
grant execute on function public.mzad_admin_review_device_verification(uuid,text,text,jsonb) to authenticated;

commit;

-- Notes:
-- 1) The checklist is stored as audit evidence; the admin UI must send a JSON object.
-- 2) Duplicate IMEI/serial identifiers block approval but do not auto-ban the user.
-- 3) This does not prove an IMEI is authentic; staff must compare it with physical device evidence.
-- 4) Apply only after checking this migration against the actual deployed Supabase schema in staging.
