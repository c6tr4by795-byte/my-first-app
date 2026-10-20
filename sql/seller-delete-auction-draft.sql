-- MZAD PHONE: permanent deletion for seller-owned, non-active auctions.
-- Live/scheduled auctions remain untouched.
-- Deposits and payment requests are preserved; an auction can only be deleted
-- after every linked deposit has status='refunded'. Run this migration in Supabase SQL Editor.

begin;

create or replace function public.mzad_seller_delete_auction_draft(
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
  v_status text;
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

  v_status := lower(coalesce(v_auction.status, ''));

  -- Never delete an auction that is live or waiting to open.
  if v_status in ('live', 'scheduled', 'active', 'pending', 'pending_approval', 'awaiting_approval') then
    raise exception 'AUCTION_IS_ACTIVE';
  end if;

  -- Only terminal auctions and drafts are eligible for deletion.
  if v_status not in ('draft', 'ended', 'completed', 'cancelled', 'rejected', 'expired') then
    raise exception 'AUCTION_REQUIRES_ADMIN_REVIEW';
  end if;

  -- Do not erase records needed for a transaction, dispute, or fraud review.
  if exists (select 1 from public.mzad_transactions t where t.auction_id = p_auction_id) then
    raise exception 'AUCTION_HAS_PROTECTED_TRANSACTION';
  end if;
  if exists (select 1 from public.mzad_disputes d where d.auction_id = p_auction_id) then
    raise exception 'AUCTION_HAS_PROTECTED_DISPUTE';
  end if;
  if exists (select 1 from public.mzad_fraud_flags f where f.auction_id = p_auction_id) then
    raise exception 'AUCTION_HAS_PROTECTED_FRAUD_REVIEW';
  end if;

  -- Never delete or alter a direct-sale listing from this auction action.
  -- Any linked deposits must already be marked refunded. Keep deposit/payment
  -- history, but detach the refunded deposit from the auction before deletion.
  if exists (
    select 1
      from public.mzad_deposits d
     where d.auction_id = p_auction_id
       and lower(coalesce(d.status, '')) <> 'refunded'
  ) then
    raise exception 'AUCTION_HAS_PROTECTED_DEPOSIT';
  end if;

  update public.mzad_deposits
     set auction_id = null
   where auction_id = p_auction_id
     and lower(coalesce(status, '')) = 'refunded';

  -- Child auction records with cascading FKs are removed with the auction.
  -- Keep the device and its photos. Unlock it only when no other active auction
  -- is using the same device.
  update public.mzad_devices d
     set locked_for_auction = false
   where d.id = v_auction.device_id
     and not exists (
       select 1
         from public.mzad_auctions other
        where other.device_id = v_auction.device_id
          and other.id <> p_auction_id
          and lower(coalesce(other.status, '')) in ('live', 'scheduled', 'active')
     );

  delete from public.mzad_auctions
   where id = p_auction_id;

  return jsonb_build_object(
    'ok', true,
    'auction_id', p_auction_id,
    'deleted', true,
    'storage_paths', '[]'::jsonb,
    'message', 'تم حذف المزاد نهائياً. بقي الجهاز وسجل التأمين وإثباتات الدفع محفوظة.'
  );
end;
$$;

revoke all on function public.mzad_seller_delete_auction_draft(uuid) from public, anon;
grant execute on function public.mzad_seller_delete_auction_draft(uuid) to authenticated;

commit;
