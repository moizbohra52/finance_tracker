-- Phase 08: custom recurring schedules ("every 2 weeks", "every 45 days").
--
-- recurring_transactions.frequency stays one of daily/weekly/monthly/yearly;
-- interval_count says how many of that unit pass between occurrences.
-- Existing rows keep running every 1 unit. No new table, so RLS is unchanged
-- (the existing owner-only policies already cover the new column).

alter table public.recurring_transactions
  add column interval_count integer not null default 1
    check (interval_count between 1 and 365);
