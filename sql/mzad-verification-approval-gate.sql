-- MZAD PHONE: require an approved inspection report for verification approval.
-- Staging only until deployed schema and RLS have been verified.
begin;

create or replace function public.mzad_admin_require_inspection_report(p_device_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.mzad_is_admin() then
    raise exception 'ADMIN_REQUIRED';
  end if;

  if not exists (
    select 1
      from public.mzad_device_inspections i
      join public.mzad_inspection_reports r on r.inspection_id=i.id
     where i.device_id=p_device_id
       and i.status='approved'
  ) then
    raise exception 'APPROVED_INSPECTION_REPORT_REQUIRED';
  end if;

  return true;
end;
$$;

revoke all on function public.mzad_admin_require_inspection_report(uuid) from public, anon;
grant execute on function public.mzad_admin_require_inspection_report(uuid) to authenticated;

commit;

-- Important: this guard is an explicit callable precondition, not an automatic hook.
-- The final approval RPC must invoke it internally before setting verification_status='approved'.
-- Do not treat this helper alone as enforcement until that integration is completed and tested.
