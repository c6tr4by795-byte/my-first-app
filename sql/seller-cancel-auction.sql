-- MZAD PHONE: safe seller cancellation of an auction
-- Run this file in Supabase SQL Editor before using the "إلغاء المزاد" button.
-- This intentionally preserves the auction, bids, device, images, and deposit records.
begin;

alter table public.mzad_auctions
  add column if not exists seller_cancelled_at timestamptz,
  add column if not exists seller_cancel_reason text;

create or replace function public.mzad_seller_cancel_auction(
  p_auction_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_auction public.mzad_auctions%rowtype;
  v_was_live boolean := false;
begin
  if v_user is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select *
    into v_auction
    from public.mzad_auctions
   where id = p_auction_id
   for update;

  if not found then
    raise exception 'AUCTION_NOT_FOUND';
  end if;

  if v_auction.seller_user_id <> v_user and not public.mzad_is_admin() then
    raise exception 'NOT_AUCTION_OWNER';
  end if;

  if v_auction.status in ('ended','completed','cancelled','rejected') then
    raise exception 'AUCTION_HAS_ENDED';
  end if;

  v_was_live := v_auction.status = 'live';

  -- Keep the original ends_at for the deposit/refund review timeline.
  -- Do not delete bids, deposits, payment requests, the device, or its photos.
  update public.mzad_auctions
     set status = 'cancelled',
         seller_cancelled_at = now(),
         seller_cancel_reason = 'إلغاء بطلب البائع'
   where id = p_auction_id;

  -- Make the device available again, without deleting the device itself.
  update public.mzad_devices
     set locked_for_auction = false
   where id = v_auction.device_id
     and owner_user_id = v_user;

  return jsonb_build_object(
    'ok', true,
    'auction_id', p_auction_id,
    'was_live', v_was_live,
    'deposit_refund_after', v_auction.ends_at,
    'message', case
      when v_was_live then 'تم إلغاء المزاد. يبقى التأمين محفوظاً إلى موعد النهاية الأصلي، ثم تراجع الإدارة لاسترداده.'
      else 'تم إلغاء المزاد. سجل المزاد والتأمين محفوظان للمراجعة.'
    end
  );
end;
$$;

revoke all on function public.mzad_seller_cancel_auction(uuid) from public, anon;
grant execute on function public.mzad_seller_cancel_auction(uuid) to authenticated;

commit;
