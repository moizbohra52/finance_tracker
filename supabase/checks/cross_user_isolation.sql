-- Cross-user isolation and integrity checks for the Phase 01 schema.
--
-- Run against a LOCAL or DEVELOPMENT database after all migrations:
--   psql "$DATABASE_URL" -f supabase/checks/cross_user_isolation.sql
-- or paste into the Supabase SQL Editor. Never run against production.
--
-- Everything runs in one transaction that is rolled back, so no data is left
-- behind. The first failing check raises an exception starting with "FAIL:".
-- Reaching the end prints the notice "All cross-user isolation checks passed".
--
-- Users are simulated the same way PostgREST does it: role `authenticated`
-- plus the JWT claims in request.jwt.claims, which auth.uid() reads.

begin;

-- ---------------------------------------------------------------------------
-- Setup as the database owner: two users. The signup trigger must create a
-- profile and settings row for each.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'rls-check-a@example.test', '{"full_name": "User A"}'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'rls-check-b@example.test', '{"full_name": "User B"}');

do $$
begin
  if (select full_name from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') is distinct from 'User A' then
    raise exception 'FAIL: signup trigger did not create profile with full_name';
  end if;
  if (select count(*) from public.user_settings where user_id in ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')) <> 2 then
    raise exception 'FAIL: signup trigger did not create user_settings';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- User A creates one row in every table, without sending user_id.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "role": "authenticated"}', true);
set local role authenticated;

insert into public.accounts (id, name, type, opening_balance, opening_balance_date, updated_at)
values
  ('a1000000-0000-4000-8000-000000000001', 'A Cash', 'cash', 1000, '2026-01-01', '2000-01-01'),
  ('a1000000-0000-4000-8000-000000000002', 'A Bank', 'bank', -250.50, '2026-01-01', '2000-01-01');
insert into public.categories (id, name, type)
values ('a2000000-0000-4000-8000-000000000001', 'A Pets', 'expense');
insert into public.contacts (id, name, opening_balance, opening_balance_type)
values ('a3000000-0000-4000-8000-000000000001', 'A Friend', 500, 'receivable');
insert into public.transactions (id, account_id, category_id, type, amount)
values ('a4000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000101', 'income', 45000);
insert into public.transactions (account_id, type, amount, transfer_id)
values
  ('a1000000-0000-4000-8000-000000000001', 'transfer_out', 200, 'a5000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000002', 'transfer_in', 200, 'a5000000-0000-4000-8000-000000000001');
insert into public.contact_transactions (contact_id, type, amount, due_date)
values ('a3000000-0000-4000-8000-000000000001', 'credit', 5000, '2026-12-31');
insert into public.budgets (category_id, amount, period_type, start_date)
values ('a2000000-0000-4000-8000-000000000001', 3000, 'monthly', '2026-10-01');
insert into public.recurring_transactions (account_id, category_id, type, amount, frequency, start_date, next_run_at)
values ('a1000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000206', 'expense', 15000, 'monthly', '2026-10-01', '2026-11-01T00:00:00Z');
insert into public.reminders (contact_id, account_id, title, amount, remind_at)
values ('a3000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'Collect from A Friend', 5000, '2026-12-31T04:30:00Z');
insert into public.notifications (title, body, type)
values ('Welcome', 'Your account is ready.', 'security');
update public.profiles set mobile = '+910000000000';

do $$
declare
  a constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
begin
  if exists (select 1 from public.accounts where user_id is distinct from a) then
    raise exception 'FAIL: user_id did not default to auth.uid()';
  end if;
  if exists (select 1 from public.accounts where updated_at < '2001-01-01') then
    raise exception 'FAIL: client-supplied updated_at was not replaced by server time';
  end if;
  if (select mobile from public.profiles) is distinct from '+910000000000' then
    raise exception 'FAIL: user could not update own profile';
  end if;
  if (select count(*) from public.categories where is_system) <> 25 then
    raise exception 'FAIL: system categories are not readable';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- User B: must not read, change or reference anything of A.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "role": "authenticated"}', true);
set local role authenticated;

insert into public.accounts (id, name, type, opening_balance_date)
values ('b1000000-0000-4000-8000-000000000001', 'B Cash', 'cash', '2026-01-01');

do $$
declare
  a constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b constant uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  affected bigint;
begin
  -- Reads
  if (select count(*) from public.profiles) <> 1 or (select count(*) from public.profiles where id = a) <> 0 then
    raise exception 'FAIL: B can read profiles other than its own';
  end if;
  if (select count(*) from public.user_settings where user_id = a) <> 0 then
    raise exception 'FAIL: B can read A settings';
  end if;
  if (select count(*) from public.accounts) <> 1 then
    raise exception 'FAIL: B can read A accounts';
  end if;
  if (select count(*) from public.categories where not is_system) <> 0 then
    raise exception 'FAIL: B can read A custom categories';
  end if;
  if (select count(*) from public.contacts)
     + (select count(*) from public.transactions)
     + (select count(*) from public.contact_transactions)
     + (select count(*) from public.budgets)
     + (select count(*) from public.recurring_transactions)
     + (select count(*) from public.reminders)
     + (select count(*) from public.notifications) <> 0 then
    raise exception 'FAIL: B can read A financial rows';
  end if;

  -- Updates and deletes of A rows silently match nothing
  update public.accounts set name = 'hacked' where id = 'a1000000-0000-4000-8000-000000000001';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: B updated an A account'; end if;

  update public.transactions set amount = 1 where user_id = a;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: B updated A transactions'; end if;

  update public.profiles set full_name = 'hacked' where id = a;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: B updated the A profile'; end if;

  delete from public.transactions where user_id = a;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: B deleted A transactions'; end if;

  delete from public.contacts where user_id = a;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: B deleted A contacts'; end if;

  update public.categories set name = 'hacked' where is_system;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: B updated a system category'; end if;

  -- Inserting rows owned by A
  begin
    insert into public.accounts (user_id, name, type, opening_balance_date)
    values (a, 'planted', 'cash', '2026-01-01');
    raise exception 'FAIL: B inserted an account owned by A';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.notifications (user_id, title, type) values (a, 'phish', 'security');
    raise exception 'FAIL: B inserted a notification for A';
  exception when insufficient_privilege then null;
  end;

  -- Referencing A rows from B rows
  begin
    insert into public.transactions (account_id, type, amount)
    values ('a1000000-0000-4000-8000-000000000001', 'expense', 10);
    raise exception 'FAIL: B created a transaction on an A account';
  exception when foreign_key_violation then null;
  end;

  begin
    insert into public.contact_transactions (contact_id, type, amount)
    values ('a3000000-0000-4000-8000-000000000001', 'debit', 10);
    raise exception 'FAIL: B created a ledger entry for an A contact';
  exception when foreign_key_violation then null;
  end;

  begin
    insert into public.reminders (contact_id, title, remind_at)
    values ('a3000000-0000-4000-8000-000000000001', 'probe', now());
    raise exception 'FAIL: B created a reminder for an A contact';
  exception when foreign_key_violation then null;
  end;

  begin
    insert into public.transactions (account_id, category_id, type, amount)
    values ('b1000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'expense', 10);
    raise exception 'FAIL: B used an A custom category on a transaction';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.budgets (category_id, amount, period_type, start_date)
    values ('a2000000-0000-4000-8000-000000000001', 10, 'monthly', '2026-10-01');
    raise exception 'FAIL: B used an A custom category on a budget';
  exception when insufficient_privilege then null;
  end;

  -- Creating a shared system category or handing a row to A
  begin
    insert into public.categories (user_id, name, type, is_system)
    values (null, 'planted', 'expense', true);
    raise exception 'FAIL: B created a system category';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.accounts set user_id = a where user_id = b;
    raise exception 'FAIL: B transferred ownership of an account to A';
  exception when insufficient_privilege then null;
  end;

  -- Profiles are created by the signup trigger and removed with the user
  begin
    insert into public.profiles (id) values (gen_random_uuid());
    raise exception 'FAIL: B inserted a profile';
  exception when insufficient_privilege then null;
  end;

  begin
    delete from public.profiles;
    raise exception 'FAIL: B deleted its profile directly';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Anonymous (signed out) clients have no table access at all.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
set local role anon;

do $$
begin
  begin
    perform 1 from public.accounts;
    raise exception 'FAIL: anon can query accounts';
  exception when insufficient_privilege then null;
  end;

  begin
    perform 1 from public.categories;
    raise exception 'FAIL: anon can query categories';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Integrity rules, as user A.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "role": "authenticated"}', true);
set local role authenticated;

do $$
begin
  begin
    delete from public.accounts where id = 'a1000000-0000-4000-8000-000000000001';
    raise exception 'FAIL: an account with transactions was hard-deleted';
  exception when foreign_key_violation then null;
  end;

  begin
    insert into public.transactions (account_id, type, amount, transfer_id)
    values ('a1000000-0000-4000-8000-000000000002', 'transfer_out', 200, 'a5000000-0000-4000-8000-000000000001');
    raise exception 'FAIL: a transfer accepted a third leg';
  exception when unique_violation then null;
  end;

  begin
    insert into public.transactions (account_id, type, amount, transfer_id)
    values
      ('a1000000-0000-4000-8000-000000000001', 'transfer_out', 50, 'a5000000-0000-4000-8000-000000000002'),
      ('a1000000-0000-4000-8000-000000000001', 'transfer_in', 50, 'a5000000-0000-4000-8000-000000000002');
    raise exception 'FAIL: a transfer used the same account for both legs';
  exception when unique_violation then null;
  end;

  begin
    insert into public.transactions (account_id, type, amount)
    values ('a1000000-0000-4000-8000-000000000001', 'transfer_in', 50);
    raise exception 'FAIL: a transfer leg was accepted without transfer_id';
  exception when check_violation then null;
  end;

  begin
    insert into public.transactions (account_id, type, amount)
    values ('a1000000-0000-4000-8000-000000000001', 'expense', 0);
    raise exception 'FAIL: a zero amount was accepted';
  exception when check_violation then null;
  end;

  begin
    insert into public.contact_transactions (contact_id, type, amount)
    values ('a3000000-0000-4000-8000-000000000001', 'credit', -5);
    raise exception 'FAIL: a negative ledger amount was accepted';
  exception when check_violation then null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Deleting an auth user removes all of that user's data and nothing else.
-- ---------------------------------------------------------------------------
reset role;
delete from auth.users where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

do $$
declare
  a constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
begin
  if exists (select 1 from public.profiles where id = a)
     or exists (select 1 from public.user_settings where user_id = a)
     or exists (select 1 from public.accounts where user_id = a)
     or exists (select 1 from public.categories where user_id = a)
     or exists (select 1 from public.contacts where user_id = a)
     or exists (select 1 from public.transactions where user_id = a)
     or exists (select 1 from public.contact_transactions where user_id = a)
     or exists (select 1 from public.budgets where user_id = a)
     or exists (select 1 from public.recurring_transactions where user_id = a)
     or exists (select 1 from public.reminders where user_id = a)
     or exists (select 1 from public.notifications where user_id = a) then
    raise exception 'FAIL: deleting the auth user left data behind';
  end if;
  if not exists (select 1 from public.accounts where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then
    raise exception 'FAIL: deleting user A removed user B data';
  end if;
  if (select count(*) from public.categories where is_system) <> 25 then
    raise exception 'FAIL: deleting a user removed system categories';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Self-service deletion (public.delete_my_account).
-- ---------------------------------------------------------------------------
set local role anon;
do $$
begin
  perform public.delete_my_account();
  raise exception 'FAIL: anon can call delete_my_account';
exception when insufficient_privilege then null;
end $$;

-- B signed in an hour ago: a recent password sign-in is required.
reset role;
select set_config('request.jwt.claims', json_build_object(
  'sub', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'role', 'authenticated',
  'amr', json_build_array(json_build_object('method', 'password', 'timestamp', extract(epoch from now() - interval '1 hour')::bigint))
)::text, true);
set local role authenticated;
do $$
begin
  perform public.delete_my_account();
  raise exception 'FAIL: delete_my_account accepted a stale sign-in';
exception when insufficient_privilege then null;
end $$;

-- B just re-entered the password: deletion succeeds and removes B's data.
reset role;
select set_config('request.jwt.claims', json_build_object(
  'sub', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'role', 'authenticated',
  'amr', json_build_array(json_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint))
)::text, true);
set local role authenticated;
select public.delete_my_account();

reset role;
do $$
begin
  if exists (select 1 from auth.users where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
     or exists (select 1 from public.accounts where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
     or exists (select 1 from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then
    raise exception 'FAIL: delete_my_account left the user or their data behind';
  end if;
  if (select count(*) from public.categories where is_system) <> 25 then
    raise exception 'FAIL: delete_my_account removed system categories';
  end if;

  raise notice 'All cross-user isolation checks passed';
end $$;

rollback;
