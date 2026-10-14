-- MZAD PHONE: 4-hour reservation window + authentic auction views
-- IMPORTANT: review against the live schema before applying to production.
-- This migration uses the deployed legacy names described by the current project.
begin;

-- Count one authenticated user's view per auction per calendar day.
create table if not exists public.mzad_auction_views (
  id bigint generated always as identity primary key,
  auction_id uuid not null references public.mzad_auctions(id) on delete cascade,
  viewer_user_id uuid not null references auth.users(id) on delete cascade,
  viewed_on date not null default (timezone('utc', now()))::date,
  viewed_at timestamptz not null default now(),
  constraint mzad_auction_views_one_per_user_day unique (auction_id, viewer_user_id, viewed_on)
);

alter table public.mzad_auction_views enable row level security;
revoke all on public.mzad_auction_views from anon, authenticated;

create or replace function public.mzad_register_auction_view(p_auction_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_count bigint;
begin
  if v_user is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not exists (select 1 from public.mzad_auctions where id = p_auction_id) then
    raise exception 'AUCTION_NOT_FOUND';
  end if;

  insert into public.mzad_auction_views(auction_id, viewer_user_id, viewed_on)
  values (p_auction_id, v_user, (timezone('utc', now()))::date)
  on conflict (auction_id, viewer_user_id, viewed_on) do nothing;

  select count(*) into v_count
  from public.mzad_auction_views
  where auction_id = p_auction_id;

  return v_count;
end;
$$;

create or replace function public.mzad_get_auction_view_count(p_auction_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $
  select count(*)::bigint
  from public.mzad_auction_views
  where auction_id = p_auction_id
    and exists (select 1 from public.mzad_auctions a where a.id = p_auction_id);
$;

create or replace function public.mzad_get_auction_reservation_count(p_auction_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $
  select count(distinct d.user_id)::bigint
  from public.mzad_deposits d
  where d.auction_id = p_auction_id
    and d.deposit_type = 'auction_buyer'
    and d.status not in ('rejected','cancelled','refunded','forfeited')
    and exists (select 1 from public.mzad_auctions a where a.id = p_auction_id);
$;

revoke all on function public.mzad_register_auction_view(uuid) from public, anon;
grant execute on function public.mzad_register_auction_view(uuid) to authenticated;
revoke all on function public.mzad_get_auction_view_count(uuid) from public, anon;
grant execute on function public.mzad_get_auction_view_count(uuid) to authenticated;
revoke all on function public.mzad_get_auction_reservation_count(uuid) from public, anon;
grant execute on function public.mzad_get_auction_reservation_count(uuid) to authenticated;

-- Once the seller deposit is approved, keep the auction scheduled for 4 hours.
-- Existing lifecycle cron moves scheduled auctions to live at starts_at.
create or replace function public.mzad_activate_seller_auction_after_deposit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_duration bigint;
  v_start timestamptz;
  v_end timestamptz;
begin
  if new.status <> 'approved'
     or old.status is not distinct from new.status
     or new.deposit_type <> 'auction_seller'
     or new.auction_id is null then
    return new;
  end if;

  select coalesce(public.mzad_setting_bigint('auction_duration_seconds', 3600), 3600)
    into v_duration;
  v_duration := greatest(v_duration, 60);
  v_start := now() + interval '4 hours';
  v_end := v_start + make_interval(secs => v_duration::double precision);

  update public.mzad_auctions
     set status = 'scheduled',
         starts_at = v_start,
         ends_at = v_end,
         original_ends_at = v_end,
         ended_at = null,
         updated_at = now()
   where id = new.auction_id
     and seller_user_id = new.user_id
     and status = 'draft';

  return new;
end;
$$;

commit;

-- View count is unique authenticated viewers per UTC day, not raw page refreshes.
-- Reservation count should be based on buyer deposits with status approved/proof_submitted,
-- after confirming the exact legacy status values in production.
