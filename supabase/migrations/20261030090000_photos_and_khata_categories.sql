-- Photos for khata contacts and split groups, and the system categories that
-- the account rows of khata entries get (docs/03_DATABASE_SCHEMA.md).
--
-- avatar_url is an object name in the private `avatars` bucket, never a URL:
-- "<user id>/contacts/<contact id>-<ms>.<ext>" or "<user id>/groups/...". The
-- bucket's policies (20261008120000_profile_settings.sql) already limit a user
-- to their own first folder, so no new policy is needed.
--
-- Apply before shipping the app version that sets photos. Until then setting
-- a photo stays queued (the column is missing), and transactions that name
-- the new categories fail their foreign key and stay queued too; nothing else
-- is affected, because contact and group saves do not send avatar_url.

alter table public.contacts add column if not exists avatar_url text;
alter table public.split_groups add column if not exists avatar_url text;

-- Ids are fixed so the app's local database seeds identical rows offline.
insert into public.categories (id, user_id, name, type, icon, is_system)
values
  ('c0000000-0000-4000-8000-000000000108', null, 'Money Borrowed', 'income', 'borrowed', true),
  ('c0000000-0000-4000-8000-000000000109', null, 'Repayment Received', 'income', 'repayment_received', true),
  ('c0000000-0000-4000-8000-000000000219', null, 'Money Lent', 'expense', 'lent', true),
  ('c0000000-0000-4000-8000-000000000220', null, 'Repayment Made', 'expense', 'repayment_made', true)
on conflict (id) do nothing;
