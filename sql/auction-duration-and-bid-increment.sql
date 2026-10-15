-- MZAD PHONE: seller-selected auction duration and price-based minimum bid increment
-- Run once in Supabase SQL Editor after deploying the matching sell-auction.html.
begin;

alter table public.mzad_auctions
  add column if not exists duration_hours integer not null default 1;

alter table public.mzad_auctions
  drop constraint if exists mzad_auctions_duration_hours_check;

alter table public.mzad_auctions
  add constraint mzad_auctions_duration_hours_check
  check (duration_hours in (1, 4, 8));

-- Replace the old RPC signature so all new drafts save the chosen duration.
drop function if exists public.mzad_create_auction_draft(uuid, bigint);

create or replace function public.mzad_create_auction_draft(
  p_device_id uuid,
  p_starting_price_iqd bigint,
  p_duration_hours integer default 1
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
  v_duration_hours integer;
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

  if p_duration_hours is null or p_duration_hours not in (1, 4, 8) then
    raise exception 'INVALID_AUCTION_DURATION';
  end if;

  v_duration_hours := p_duration_hours;

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

  v_increment := case when p_starting_price_iqd >= 400000 then 10000 else 5000 end;

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
    duration_hours,
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
    v_duration_hours,
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

revoke all on function public.mzad_create_auction_draft(uuid, bigint, integer) from public, anon;
grant execute on function public.mzad_create_auction_draft(uuid, bigint, integer) to authenticated;


-- When the seller deposit is approved and the auction actually becomes live,
-- start the selected duration then (not while the draft is waiting for review).
-- Admin approval starts a fixed four-hour reservation window.
-- The auction's selected duration begins only when the scheduled auction is activated.
create or replace function public.mzad_apply_selected_auction_duration()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'scheduled' and old.status is distinct from 'scheduled' then
    new.starts_at := now() + interval '4 hours';
    new.ends_at := new.starts_at + make_interval(hours => coalesce(new.duration_hours, 1));
    new.original_ends_at := new.ends_at;
  elsif new.status = 'live' and old.status is distinct from 'live' then
    -- Preserve the approved opening time and duration. The activation function
    -- should only move status to live when starts_at is due.
    if new.starts_at is null or new.starts_at > now() then
      raise exception 'AUCTION_OPENING_TIME_NOT_REACHED';
    end if;
    new.ends_at := new.starts_at + make_interval(hours => coalesce(new.duration_hours, 1));
    new.original_ends_at := new.ends_at;
  end if;
  return new;
end;
$$;

drop trigger if exists zz_mzad_apply_selected_auction_duration on public.mzad_auctions;
create trigger zz_mzad_apply_selected_auction_duration
before update of status on public.mzad_auctions
for each row
execute function public.mzad_apply_selected_auction_duration();

commit;
