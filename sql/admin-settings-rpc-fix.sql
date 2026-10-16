-- MZAD PHONE: repair admin settings save RPC
-- Run once in Supabase SQL Editor. Does not modify auction/deposit workflows.

begin;

create or replace function public.mzad_admin_update_setting(
  p_key text,
  p_value jsonb,
  p_description_ar text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := btrim(coalesce(p_key, ''));
  v_row public.mzad_settings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not coalesce(public.mzad_is_admin(), false) then
    raise exception 'ADMIN_REQUIRED';
  end if;

  if v_key = '' or length(v_key) > 120 then
    raise exception 'INVALID_SETTING_KEY';
  end if;

  if p_value is null then
    raise exception 'SETTING_VALUE_REQUIRED';
  end if;

  insert into public.mzad_settings (key, value_json, description_ar, updated_at)
  values (v_key, p_value, p_description_ar, now())
  on conflict (key) do update
    set value_json = excluded.value_json,
        description_ar = coalesce(excluded.description_ar, public.mzad_settings.description_ar),
        updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'key', v_row.key,
    'value_json', v_row.value_json,
    'updated_at', v_row.updated_at
  );
end;
$$;

revoke all on function public.mzad_admin_update_setting(text, jsonb, text) from public, anon;
grant execute on function public.mzad_admin_update_setting(text, jsonb, text) to authenticated;

commit;
