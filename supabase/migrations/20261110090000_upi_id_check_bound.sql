-- Fix: saving a UPI ID never synced.
--
-- The CHECK added in 20261021090000_user_settings_upi_id.sql let the part
-- before the "@" repeat up to 256 times. Postgres allows a repetition count
-- of at most 255, and it only compiles the pattern when a non-null upi_id is
-- first written. So that migration applied cleanly, and afterwards every
-- settings upload that carried a UPI ID was rejected with
-- "invalid regular expression: invalid repetition count(s)" (SQLSTATE 2201B).
-- The app kept the UPI ID on the device and showed "Update Settings" as
-- failed in the sync queue.
--
-- No row can hold a UPI ID yet, so re-adding the constraint has only NULLs
-- to check. The pattern is the same as Validators.upiIdPattern in the app.
-- Once this is applied, the next sync uploads the queued settings on its own.

alter table public.user_settings
  drop constraint user_settings_upi_id_check,
  add constraint user_settings_upi_id_check
    check (upi_id is null or upi_id ~ '^[a-zA-Z0-9._-]{2,255}@[a-zA-Z]{2,64}$');
