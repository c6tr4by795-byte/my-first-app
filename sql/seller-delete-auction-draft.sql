-- MZAD PHONE: permanent deletion of an unused auction draft only.
-- Run in Supabase SQL Editor before using "حذف نهائي".
-- Safety: refuses live/scheduled/ended auctions and any auction with bids or deposits.
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

  if v_auction.status <> 'draft' then
    raise exception 'AUCTION_HAS_ACTIVITY';
  end if;

  if exists (
    select 1 from public.mzad_auction_bids b
    where b.auction_id = p_auction_id
  ) then
    raise exception 'AUCTION_HAS_ACTIVITY';
  end if;

  if exists (
    select 1 from public.mzad_deposits d
    where d.auction_id = p_auction_id
  ) then
    raise exception 'AUCTION_HAS_ACTIVITY';
  end if;

  -- Only unlock the device; do not delete the user's device or its photos.
  update public.mzad_devices
     set locked_for_auction = false
   where id = v_auction.device_id
     and owner_user_id = v_user;

  -- The FK may reject deletion if another table still references this draft.
  -- In that case PostgreSQL rolls back and nothing is partially deleted.
  delete from public.mzad_auctions
   where id = p_auction_id;

  return jsonb_build_object(
    'ok', true,
    'auction_id', p_auction_id,
    'deleted', true,
    'message', 'تم حذف مسودة المزاد نهائياً. لم يتم حذف الجهاز أو صوره.'
  );
end;
$$;

revoke all on function public.mzad_seller_delete_auction_draft(uuid) from public, anon;
grant execute on function public.mzad_seller_delete_auction_draft(uuid) to authenticated;

commit;
