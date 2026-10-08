-- Phase 09: reminder types, snooze and transaction link, and FCM device
-- tokens. Existing owner-only RLS policies on public.reminders already cover
-- the new columns; device_tokens gets its own below.

-- ---------------------------------------------------------------------------
-- reminders
-- ---------------------------------------------------------------------------
-- A reminder may point at one of the user's transactions. transactions had no
-- (user_id, id) key, which the composite foreign key needs so a reminder can
-- never reference another user's transaction.
alter table public.transactions
  add constraint transactions_user_id_id_key unique (user_id, id);

alter table public.reminders
  add column reminder_type text not null default 'custom'
    check (reminder_type in (
      'payment', 'receivable', 'payable', 'khata', 'recurring', 'custom'
    )),
  -- While set and in the future, this replaces remind_at as the fire time.
  -- remind_at keeps the original schedule, so snoozing a monthly reminder
  -- never moves the series.
  add column snoozed_until timestamptz,
  add column transaction_id uuid,
  add constraint reminders_repeat_rule_check
    check (repeat_rule is null
           or repeat_rule in ('daily', 'weekly', 'monthly', 'yearly')),
  add constraint reminders_user_transaction_fkey
    foreign key (user_id, transaction_id)
    references public.transactions (user_id, id);

create index reminders_user_transaction_idx
  on public.reminders (user_id, transaction_id)
  where transaction_id is not null;

-- ---------------------------------------------------------------------------
-- device_tokens: one FCM token per user and install. Written by the app,
-- read by the server-side sender (service role, never shipped in Flutter).
-- ---------------------------------------------------------------------------
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  token text not null check (btrim(token) <> ''),
  platform text not null check (platform in ('android', 'ios')),
  -- Random id the app generates once per install.
  device_id text not null check (btrim(device_id) <> ''),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, device_id)
);

create trigger set_updated_at
  before insert or update on public.device_tokens
  for each row execute function private.set_updated_at();

alter table public.device_tokens enable row level security;

revoke all on table public.device_tokens from anon, authenticated;
grant select, insert, update, delete on table public.device_tokens
  to authenticated;

create policy "Users can view their own device tokens"
  on public.device_tokens for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own device tokens"
  on public.device_tokens for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own device tokens"
  on public.device_tokens for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own device tokens"
  on public.device_tokens for delete to authenticated
  using (user_id = (select auth.uid()));
