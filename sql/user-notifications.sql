-- MZAD PHONE: in-app user notifications
-- Run once in Supabase SQL Editor. This migration does not modify auction, deposit, or payment workflows.

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

-- Clients cannot create notifications for arbitrary users.
revoke all on public.mzad_notifications from anon, authenticated;
grant select on public.mzad_notifications to authenticated;
grant update (is_read) on public.mzad_notifications to authenticated;

commit;
