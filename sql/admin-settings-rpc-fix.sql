-- MZAD PHONE: safe repair for admin settings save RPC
-- Preserves the existing BOOLEAN return type, allow-list, and audit logging.
-- Run once in Supabase SQL Editor.

begin;

create or replace function public.mzad_admin_update_setting(
  p_key text,
  p_value jsonb,
  p_description_ar text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_key text := btrim(coalesce(p_key, ''));
  v_before jsonb;
  v_after jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not coalesce(public.mzad_is_admin(), false) then
    raise exception 'ADMIN_REQUIRED';
  end if;

  if v_key = '' then
    raise exception 'SETTING_KEY_REQUIRED';
  end if;

  if v_key not in (
    'auctions_enabled',
    'bidding_enabled',
    'direct_sales_enabled',
    'registration_enabled',
    'device_submissions_enabled',
    'deposits_enabled',
    'public_devices_enabled',
    'notifications_enabled',
    'maintenance_mode',
    'auction_duration_seconds',
    'auction_buyer_deposit_iqd',
    'auction_seller_deposit_iqd',
    'direct_buyer_deposit_iqd',
    'seller_platform_fee_iqd',
    'buyer_platform_fee_iqd',
    'auction_bid_increment_iqd',
    'anti_snipe_window_seconds',
    'anti_snipe_extension_seconds',
    'anti_snipe_max_extensions',
    'deposit_refund_rules'
  ) then
    raise exception 'SETTING_NOT_ALLOWED';
  end if;

  select jsonb_build_object(
    'key', s.key,
    'value_json', s.value_json,
    'description_ar', s.description_ar,
    'updated_by', s.updated_by,
    'updated_at', s.updated_at
  )
  into v_before
  from public.mzad_settings as s
  where s.key = v_key
  for update;

  if not found then
    raise exception 'SETTING_NOT_FOUND';
  end if;

  update public.mzad_settings as s
  set value_json = coalesce(p_value, 'null'::jsonb),
      description_ar = coalesce(p_description_ar, s.description_ar),
      updated_by = auth.uid(),
      updated_at = now()
  where s.key = v_key
  returning jsonb_build_object(
    'key', s.key,
    'value_json', s.value_json,
    'description_ar', s.description_ar,
    'updated_by', s.updated_by,
    'updated_at', s.updated_at
  )
  into v_after;

  perform public.mzad_write_audit(
    'admin_setting_changed',
    'setting',
    null,
    v_before,
    v_after,
    jsonb_build_object('setting_key', v_key)
  );

  return true;
end;
$function$;

revoke all on function public.mzad_admin_update_setting(text, jsonb, text) from public, anon;
grant execute on function public.mzad_admin_update_setting(text, jsonb, text) to authenticated;

commit;
