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

  -- Keep all deposit/payment history. Permit deleting a draft whose deposit
  -- was explicitly rejected only when no submitted/approved payment proof exists.
  -- All other non-refunded deposits must be refunded before deletion.
  if exists (
    select 1
      from public.mzad_deposits d
     where d.auction_id = p_auction_id
       and lower(coalesce(d.status, '')) <> 'refunded'
       and not (
         v_status = 'draft'
         and lower(coalesce(d.status, '')) in ('rejected', 'failed', 'cancelled', 'declined')
         and not exists (
           select 1
             from public.mzad_payment_requests pr
            where pr.deposit_id = d.id
              and lower(coalesce(pr.status, '')) in ('proof_submitted', 'approved', 'paid', 'confirmed')
         )
       )
  ) then
    raise exception 'AUCTION_HAS_PROTECTED_DEPOSIT';
  end if;

  -- Detach deposits before deleting the auction; never delete deposits or payment requests.
  update public.mzad_deposits d
     set auction_id = null
   where d.auction_id = p_auction_id
     and (
       lower(coalesce(d.status, '')) = 'refunded'
       or (
         v_status = 'draft'
         and lower(coalesce(d.status, '')) in ('rejected', 'failed', 'cancelled', 'declined')
         and not exists (
           select 1
             from public.mzad_payment_requests pr
            where pr.deposit_id = d.id
              and lower(coalesce(pr.status, '')) in ('proof_submitted', 'approved', 'paid', 'confirmed')
         )
       )
     );

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
