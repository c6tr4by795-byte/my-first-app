-- MZAD PHONE: in-app user notifications
-- Run once in Supabase SQL Editor. This migration does not change auction/deposit decisions or amounts.

begin;

create table if not exists public.mzad_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null default '',
  type text not null default 'system',
  link text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists mzad_notifications_user_created_idx
  on public.mzad_notifications (user_id, created_at desc);
create index if not exists mzad_notifications_user_unread_idx
  on public.mzad_notifications (user_id, is_read)
  where is_read = false;

alter table public.mzad_notifications enable row level security;

drop policy if exists "Users read their own notifications" on public.mzad_notifications;
create policy "Users read their own notifications"
  on public.mzad_notifications for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users mark their own notifications read" on public.mzad_notifications;
create policy "Users mark their own notifications read"
  on public.mzad_notifications for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke all on public.mzad_notifications from anon, authenticated;
grant select on public.mzad_notifications to authenticated;
grant update (is_read) on public.mzad_notifications to authenticated;

-- Internal helper: callable only by trusted database triggers (not by browser clients).
create or replace function public.mzad_insert_user_notification(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_type text default 'system',
  p_link text default '/home.html'
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if p_user_id is null or coalesce(btrim(p_title), '') = '' then
    return;
  end if;

  insert into public.mzad_notifications(user_id, title_ar, body_ar, type, data_json)
  values (
    p_user_id,
    left(p_title, 180),
    left(coalesce(p_body, ''), 1200),
    coalesce(nullif(p_type, ''), 'system'),
    jsonb_build_object('link', coalesce(nullif(p_link, ''), '/home.html'))
  );
end;
$function$;

revoke all on function public.mzad_insert_user_notification(uuid,text,text,text,text) from public, anon, authenticated;

-- Notify the owner when the deposit approval/rejection status changes.
create or replace function public.mzad_notify_deposit_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'approved' then
    perform public.mzad_insert_user_notification(
      new.user_id,
      'تمت الموافقة على التأمين',
      'وافقت إدارة مزاد فون على طلب التأمين الخاص بك.',
      'deposit_approved',
      case when new.auction_id is not null
        then '/auction-details.html?id=' || new.auction_id::text
        else '/profile.html'
      end
    );
  elsif new.status in ('rejected', 'rejected_proof') then
    perform public.mzad_insert_user_notification(
      new.user_id,
      'تم رفض إثبات التأمين',
      'لم تتم الموافقة على إثبات الدفع. افتح طلب التأمين لمراجعة الحالة وإعادة الإرسال إن كان متاحاً.',
      'deposit_rejected',
      '/profile.html'
    );
  elsif new.status = 'refundable' then
    perform public.mzad_insert_user_notification(
      new.user_id,
      'التأمين جاهز للاسترداد',
      'أصبح تأمينك مؤهلاً للاسترداد وفق إجراءات المنصة.',
      'deposit_refundable',
      '/profile.html'
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists mzad_notify_deposit_status_change on public.mzad_deposits;
create trigger mzad_notify_deposit_status_change
after update of status on public.mzad_deposits
for each row execute function public.mzad_notify_deposit_status_change();

-- Notify seller and winner when an auction becomes live, ends, or is cancelled.
create or replace function public.mzad_notify_auction_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_link text;
begin
  v_link := '/my-auction.html?id=' || new.id::text;

  -- A live notification is only sent when the auction genuinely transitions to live.
  if new.status = 'live' and old.status is distinct from 'live' then
    if new.seller_user_id is not null then
      perform public.mzad_insert_user_notification(
        new.seller_user_id,
        'بدأ مزاد جهازك',
        'تم فتح المزاد وأصبح متاحاً للمزايدة.',
        'auction_live',
        v_link
      );
    end if;
  end if;

  -- Ending an auction notifies the seller; it does not by itself declare a winner.
  if new.status = 'ended' and old.status is distinct from 'ended' then
    if new.seller_user_id is not null then
      perform public.mzad_insert_user_notification(
        new.seller_user_id,
        'انتهى مزاد جهازك',
        'انتهى المزاد. افتح صفحة المزاد لمراجعة النتيجة والخطوات التالية.',
        'auction_ended',
        v_link
      );
    end if;

    -- Only notify a winner when the auction was live and the winner is already
    -- assigned in the same transition to ended.
    if old.status = 'live'
       and new.winner_user_id is not null
       and new.winner_user_id is distinct from new.seller_user_id then
      perform public.mzad_insert_user_notification(
        new.winner_user_id,
        'مبروك! أنت الفائز بالمزاد',
        'انتهى المزاد وتم تسجيلك كفائز. افتح صفحة المزاد لمراجعة خطوات إكمال العملية والمهلة المحددة.',
        'auction_won',
        v_link
      );
    end if;
  end if;

  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    if new.seller_user_id is not null then
      perform public.mzad_insert_user_notification(
        new.seller_user_id,
        'تم إلغاء مزاد جهازك',
        'تم إلغاء المزاد. افتح حسابك لمراجعة الحالة والخطوات المتعلقة بالتأمين.',
        'auction_cancelled',
        v_link
      );
    end if;
    if new.winner_user_id is not null and new.winner_user_id is distinct from new.seller_user_id then
      perform public.mzad_insert_user_notification(
        new.winner_user_id,
        'تم إلغاء المزاد',
        'تم إلغاء المزاد الذي شاركت فيه. افتح صفحة المزاد لمراجعة التفاصيل.',
        'auction_cancelled',
        v_link
      );
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists mzad_notify_auction_status_change on public.mzad_auctions;
create trigger mzad_notify_auction_status_change
after update of status, winner_user_id on public.mzad_auctions
for each row execute function public.mzad_notify_auction_status_change();

commit;
