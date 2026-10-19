-- MZAD PHONE: permanent deletion of the current user's direct-sale listing.
-- Run this in Supabase SQL Editor before using the button on my-listings.html.
-- Refuses deletion when an auction or deposit exists, or when the sale is reserved/in handover.

begin;

create or replace function public.mzad_seller_delete_listing_permanently(
  p_device_id uuid,
  p_direct_sale_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_user uuid := auth.uid();
  v_sale public.mzad_direct_sales%rowtype;
  v_paths text[];
  v_bucket constant text := 'device-images';
begin
  if v_user is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_direct_sale_id is not null then
    select * into v_sale
      from public.mzad_direct_sales
     where id = p_direct_sale_id
       and device_id = p_device_id
       and seller_user_id = v_user
     for update;

    if not found then
      raise exception 'NOT_LISTING_OWNER';
    end if;

    if lower(coalesce(v_sale.status, '')) not in ('active','cancelled','rejected') then
      raise exception 'LISTING_HAS_ACTIVITY';
    end if;
  else
    -- Legacy listings use the separate devices table.
    if not exists (
      select 1 from public.devices
       where id = p_device_id and seller_id = v_user
    ) then
      raise exception 'NOT_LISTING_OWNER';
    end if;
  end if;

  -- Direct-sale listings are independent from auction listings.
  -- Do not block deleting a direct sale merely because an auction row happens
  -- to reference the same device ID. Keep the legacy-table guard separate.
  if p_direct_sale_id is null and exists (
    select 1 from public.mzad_auctions a where a.device_id = p_device_id
  ) then
    raise exception 'DEVICE_LINKED_TO_AUCTION';
  end if;

  if p_direct_sale_id is not null and exists (
    select 1 from public.mzad_deposits d where d.device_id = p_device_id
  ) then
    raise exception 'LISTING_HAS_ACTIVITY';
  end if;

  if p_direct_sale_id is not null then
    select coalesce(array_agg(storage_path), array[]::text[])
      into v_paths
      from public.mzad_device_images
     where device_id = p_device_id;

    -- Remove only this device's image metadata and storage objects.
    delete from public.mzad_device_images where device_id = p_device_id;

    delete from storage.objects
     where bucket_id = v_bucket
       and name = any (
         select case
           when p like 'device-images/%' then substring(p from length('device-images/') + 1)
           else p
         end
         from unnest(v_paths) as p
       );

    delete from public.mzad_direct_sales
     where id = p_direct_sale_id and seller_user_id = v_user;

    delete from public.mzad_devices
     where id = p_device_id and owner_user_id = v_user;
  else
    delete from public.devices
     where id = p_device_id and seller_id = v_user;
  end if;

  return jsonb_build_object('ok', true, 'deleted', true, 'device_id', p_device_id);
end;
$$;

revoke all on function public.mzad_seller_delete_listing_permanently(uuid,uuid) from public, anon;
grant execute on function public.mzad_seller_delete_listing_permanently(uuid,uuid) to authenticated;

commit;
