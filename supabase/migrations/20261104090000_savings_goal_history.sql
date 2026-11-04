-- Savings goal history (2026-11-04). "Add money" on a goal becomes a
-- savings_contributions row without an income: transaction_id is null and
-- added_at dates it. Every deposit is then listed in the goal's history, and
-- the goal's total stays derived (saved_amount, now the starting amount, plus
-- every live contribution), so a retried or two-device add never counts
-- twice. Existing goals keep their saved_amount; no data moves.
--
-- Run before shipping the app version that writes these rows.
--
-- The composite foreign key (user_id, transaction_id) is not checked while
-- transaction_id is null (MATCH SIMPLE), and the partial unique index on
-- (transaction_id, goal_id) treats nulls as distinct, so a goal can hold any
-- number of hand-added rows. RLS is unchanged: rows are still the owner's own.

alter table public.savings_contributions
  alter column transaction_id drop not null,
  add column added_at timestamptz,
  add constraint savings_contributions_source_check
    check ((transaction_id is null) = (added_at is not null));
