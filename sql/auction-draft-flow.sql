-- MZAD PHONE: auction draft + deposit flow
-- Run this file once in Supabase SQL Editor.

begin;

-- Enable deposits for the seller-deposit step.
insert into public.mzad_settings (key, value_json, description_ar)
values ('deposits_enabled', 'true'::jsonb, 'تشغيل التأمينات الإلكترونية')
on conflict (key) do update
set value_json = 'true'::jsonb,
    updated_at = now();

-- Seed payment methods using the canonical foundation schema.
-- Keep every method disabled until the Super Admin enters and verifies the recipient details.
insert into public.mzad_payment_methods
  (method_type, display_name_ar, recipient_name, recipient_identifier, instructions_ar, is_enabled, sort_order)
select x.method_type, x.display_name_ar, x.recipient_name, '', x.instructions_ar, false, x.sort_order
from (values
  ('mastercard'::text, 'ماستركارد'::text, 'رقم بطاقة الاستلام'::text,
   'حوّل مبلغ التأمين الظاهر في الفاتورة إلى بطاقة المنصة. اكتب رقم المرجع إن ظهر، وارفع صورة واضحة للإيصال. لا يبدأ المزاد قبل مراجعة الإدارة والموافقة على الإثبات.'::text, 1),
  ('zain_cash'::text, 'زين كاش'::text, 'رقم محفظة زين كاش'::text,
   'حوّل مبلغ التأمين الظاهر في الفاتورة إلى محفظة زين كاش التابعة للمنصة. اكتب رقم العملية وارفع صورة واضحة للإيصال. لا يبدأ المزاد قبل مراجعة الإدارة والموافقة على الإثبات.'::text, 2),
  ('phone_account'::text, 'تحويل إلى رقم الهاتف'::text, 'رقم الهاتف المستلم'::text,
   'حوّل مبلغ التأمين إلى رقم الهاتف المعتمد من إدارة المنصة، ثم اكتب رقم العملية وارفع صورة واضحة للإيصال. انتظر موافقة الإدارة قبل بدء المزاد.'::text, 3),
  ('other'::text, 'تحويل مصرفي أو طريقة أخرى'::text, 'بيانات الحساب المستلم'::text,
   'استخدم بيانات الحساب المعتمدة من الإدارة فقط. أرفق رقم التحويل وصورة الإيصال وانتظر موافقة الإدارة.'::text, 4)
) as x(method_type,display_name_ar,recipient_name,instructions_ar,sort_order)
where not exists (
  select 1 from public.mzad_payment_methods m where m.method_type=x.method_type
);

create or replace function public.mzad_create_auction_draft(
  p_device_id uuid,
  p_starting_price_iqd bigint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_device public.mzad_devices%rowtype;
  v_auction_id uuid;
  v_increment bigint;
  v_max_extensions integer;
begin
  if v_user is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  perform public.mzad_check_user_active();
  perform public.mzad_check_system_access('auctions');
  perform public.mzad_check_user_restriction(v_user, 'sell');

  if p_device_id is null then
    raise exception 'DEVICE_REQUIRED';
  end if;

  if p_starting_price_iqd is null or p_starting_price_iqd <= 0 then
    raise exception 'INVALID_STARTING_PRICE';
  end if;

  select *
    into v_device
    from public.mzad_devices
   where id = p_device_id
   for update;

  if not found then
    raise exception 'DEVICE_NOT_FOUND';
  end if;

  if v_device.owner_user_id <> v_user and not public.mzad_is_admin() then
    raise exception 'ACCESS_DENIED';
  end if;

  if v_device.locked_for_auction then
    raise exception 'DEVICE_LOCKED';
  end if;

  if exists (
    select 1
      from public.mzad_auctions a
     where a.device_id = p_device_id
       and a.status in ('draft', 'scheduled', 'live', 'ended')
  ) then
    raise exception 'AUCTION_ALREADY_EXISTS';
  end if;

  v_increment := greatest(
    coalesce(public.mzad_setting_bigint('auction_bid_increment_iqd', 1000), 1000),
    1
  );

  v_max_extensions := greatest(
    coalesce(public.mzad_setting_bigint('anti_snipe_max_extensions', 5), 5)::integer,
    0
  );

  insert into public.mzad_auctions (
    auction_number,
    device_id,
    seller_user_id,
    starting_price_iqd,
    current_price_iqd,
    bid_increment_iqd,
    status,
    starts_at,
    ends_at,
    original_ends_at,
    extension_count,
    max_extensions
  )
  values (
    public.mzad_generate_number('AUC'),
    p_device_id,
    v_device.owner_user_id,
    p_starting_price_iqd,
    p_starting_price_iqd,
    v_increment,
    'draft',
    null,
    null,
    null,
    0,
    v_max_extensions
  )
  returning id into v_auction_id;

  return v_auction_id;
end;
$$;

revoke all on function public.mzad_create_auction_draft(uuid, bigint) from public, anon;
grant execute on function public.mzad_create_auction_draft(uuid, bigint) to authenticated;

commit;

-- After running:
-- 1) Enable at least one payment method in the admin payment-method settings.
-- 2) Test with a normal signed-in seller account, not the SQL Editor session.
