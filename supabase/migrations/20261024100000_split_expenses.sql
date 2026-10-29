-- Split expenses with friends: groups, their members, expenses, each member's
-- part of an expense, and settlements (docs/05_FINANCIAL_LOGIC.md). The split
-- tables are the source of truth; the user's own expense, account movement
-- and khata entries are derived rows in transactions and contact_transactions,
-- linked through the new nullable split_expense_id / split_settlement_id
-- columns. Single-user like the rest of the app: friends are khata contacts,
-- not app users.
--
-- Same conventions as 20261023100000_savings_goals.sql and
-- 20261006120100_finance_core.sql: client UUID id, user_id defaulting to
-- auth.uid() with on delete cascade, created_at/updated_at (shared trigger),
-- deleted_at, RLS enabled, privileges revoked from anon, four owner-only
-- policies. References to the user's own rows are composite
-- (user_id, <ref>) -> parent (user_id, id). category_id follows the
-- transactions pattern (plain foreign key + private.can_use_category) because
-- system categories have no owner. Soft deletes through deleted_at.
--
-- Apply this before shipping the app version that syncs it, or its uploads for
-- the new tables fail and retry while the pull error ends every sync in the
-- error state.
--
-- Not enforced here, only by the app: the parts of one expense add up to its
-- total on both the paid and the share side, and the derived rows match the
-- parts. Offline edits upload row by row, so a check would reject a valid sync.

-- The composite foreign keys below need (user_id, id) on the parents they
-- reference. accounts, contacts and transactions already have one.
alter table public.transactions
  add constraint transactions_user_id_id_key unique (user_id, id);
alter table public.contact_transactions
  add constraint contact_transactions_user_id_id_key unique (user_id, id);

-- ---------------------------------------------------------------------------
-- split_groups
-- ---------------------------------------------------------------------------
create table public.split_groups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, id)
);

create trigger set_updated_at
  before insert or update on public.split_groups
  for each row execute function private.set_updated_at();

create index split_groups_user_idx on public.split_groups (user_id);

-- ---------------------------------------------------------------------------
-- split_group_members: contact_id null is the user themself; every group has
-- exactly one such row. Ids are deterministic (uuid v5 of
-- split-member:<group id>:<contact id | me>), so adding the same contact
-- twice, on two devices or after a removal, upserts (revives) the same row.
-- ---------------------------------------------------------------------------
create table public.split_group_members (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  group_id uuid not null,
  contact_id uuid references public.contacts (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, id),
  foreign key (user_id, group_id)
    references public.split_groups (user_id, id)
);

create trigger set_updated_at
  before insert or update on public.split_group_members
  for each row execute function private.set_updated_at();

create index split_group_members_user_idx on public.split_group_members (user_id);
create index split_group_members_group_idx
  on public.split_group_members (group_id);
create index split_group_members_contact_idx
  on public.split_group_members (contact_id) where contact_id is not null;

-- ---------------------------------------------------------------------------
-- split_expenses
-- ---------------------------------------------------------------------------
create table public.split_expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  group_id uuid not null,
  title text not null check (btrim(title) <> ''),
  total_amount numeric(18, 2) not null check (total_amount > 0),
  expense_date timestamptz not null,
  split_mode text not null
    check (split_mode in ('equal', 'exact', 'percent', 'shares')),
  category_id uuid references public.categories (id),
  account_id uuid,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, id),
  foreign key (user_id, group_id)
    references public.split_groups (user_id, id),
  foreign key (user_id, account_id)
    references public.accounts (user_id, id)
);

create trigger set_updated_at
  before insert or update on public.split_expenses
  for each row execute function private.set_updated_at();

create index split_expenses_user_idx on public.split_expenses (user_id);
create index split_expenses_group_idx on public.split_expenses (group_id);
create index split_expenses_category_idx
  on public.split_expenses (category_id) where category_id is not null;
create index split_expenses_account_idx
  on public.split_expenses (account_id) where account_id is not null;

-- ---------------------------------------------------------------------------
-- split_expense_parts: one row per member per expense holds both what they
-- paid and what their share is, so multiple payers need no extra table. The
-- sums are checked in the app, not by the database.
-- ---------------------------------------------------------------------------
create table public.split_expense_parts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  split_expense_id uuid not null,
  member_id uuid not null,
  paid_amount numeric(18, 2) not null check (paid_amount >= 0),
  share_amount numeric(18, 2) not null check (share_amount >= 0),
  share_input numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, id),
  foreign key (user_id, split_expense_id)
    references public.split_expenses (user_id, id),
  foreign key (user_id, member_id)
    references public.split_group_members (user_id, id)
);

create trigger set_updated_at
  before insert or update on public.split_expense_parts
  for each row execute function private.set_updated_at();

create index split_expense_parts_user_idx on public.split_expense_parts (user_id);
create index split_expense_parts_expense_idx
  on public.split_expense_parts (split_expense_id);
create index split_expense_parts_member_idx
  on public.split_expense_parts (member_id);

-- ---------------------------------------------------------------------------
-- split_settlements
-- ---------------------------------------------------------------------------
create table public.split_settlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  group_id uuid not null,
  from_member_id uuid not null,
  to_member_id uuid not null,
  amount numeric(18, 2) not null check (amount > 0),
  settled_at timestamptz not null,
  account_id uuid,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, id),
  check (from_member_id <> to_member_id),
  foreign key (user_id, group_id)
    references public.split_groups (user_id, id),
  foreign key (user_id, from_member_id)
    references public.split_group_members (user_id, id),
  foreign key (user_id, to_member_id)
    references public.split_group_members (user_id, id),
  foreign key (user_id, account_id)
    references public.accounts (user_id, id)
);

create trigger set_updated_at
  before insert or update on public.split_settlements
  for each row execute function private.set_updated_at();

create index split_settlements_user_idx on public.split_settlements (user_id);
create index split_settlements_group_idx on public.split_settlements (group_id);
create index split_settlements_from_idx
  on public.split_settlements (from_member_id);
create index split_settlements_to_idx
  on public.split_settlements (to_member_id);
create index split_settlements_account_idx
  on public.split_settlements (account_id) where account_id is not null;

-- ---------------------------------------------------------------------------
-- Link columns on the derived rows
-- ---------------------------------------------------------------------------
alter table public.transactions
  add column split_expense_id uuid,
  add column split_settlement_id uuid;
alter table public.transactions
  add foreign key (user_id, split_expense_id)
    references public.split_expenses (user_id, id);
alter table public.transactions
  add foreign key (user_id, split_settlement_id)
    references public.split_settlements (user_id, id);
create index transactions_split_expense_idx
  on public.transactions (split_expense_id) where split_expense_id is not null;
create index transactions_split_settlement_idx
  on public.transactions (split_settlement_id)
  where split_settlement_id is not null;

alter table public.contact_transactions
  add column split_expense_id uuid,
  add column split_settlement_id uuid;
alter table public.contact_transactions
  add foreign key (user_id, split_expense_id)
    references public.split_expenses (user_id, id);
alter table public.contact_transactions
  add foreign key (user_id, split_settlement_id)
    references public.split_settlements (user_id, id);
create index contact_transactions_split_expense_idx
  on public.contact_transactions (split_expense_id)
  where split_expense_id is not null;
create index contact_transactions_split_settlement_idx
  on public.contact_transactions (split_settlement_id)
  where split_settlement_id is not null;

-- ---------------------------------------------------------------------------
-- RLS: owner-only, like every user table
-- ---------------------------------------------------------------------------
alter table public.split_groups enable row level security;
alter table public.split_group_members enable row level security;
alter table public.split_expenses enable row level security;
alter table public.split_expense_parts enable row level security;
alter table public.split_settlements enable row level security;

revoke all on table public.split_groups from anon, authenticated;
revoke all on table public.split_group_members from anon, authenticated;
revoke all on table public.split_expenses from anon, authenticated;
revoke all on table public.split_expense_parts from anon, authenticated;
revoke all on table public.split_settlements from anon, authenticated;

grant select, insert, update, delete on table public.split_groups
  to authenticated;
grant select, insert, update, delete on table public.split_group_members
  to authenticated;
grant select, insert, update, delete on table public.split_expenses
  to authenticated;
grant select, insert, update, delete on table public.split_expense_parts
  to authenticated;
grant select, insert, update, delete on table public.split_settlements
  to authenticated;

create policy "Users can view their own split groups"
  on public.split_groups for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own split groups"
  on public.split_groups for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own split groups"
  on public.split_groups for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own split groups"
  on public.split_groups for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can view their own split group members"
  on public.split_group_members for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own split group members"
  on public.split_group_members for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own split group members"
  on public.split_group_members for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own split group members"
  on public.split_group_members for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can view their own split expenses"
  on public.split_expenses for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own split expenses"
  on public.split_expenses for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and private.can_use_category(category_id)
  );
create policy "Users can update their own split expenses"
  on public.split_expenses for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and private.can_use_category(category_id)
  );
create policy "Users can delete their own split expenses"
  on public.split_expenses for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can view their own split expense parts"
  on public.split_expense_parts for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own split expense parts"
  on public.split_expense_parts for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own split expense parts"
  on public.split_expense_parts for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own split expense parts"
  on public.split_expense_parts for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can view their own split settlements"
  on public.split_settlements for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own split settlements"
  on public.split_settlements for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own split settlements"
  on public.split_settlements for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own split settlements"
  on public.split_settlements for delete to authenticated
  using (user_id = (select auth.uid()));
