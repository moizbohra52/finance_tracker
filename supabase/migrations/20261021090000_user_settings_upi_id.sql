-- Khata statement and payment reminders: the user's own UPI ID.
--
-- The app puts it in "pay me" links (upi://pay?pa=...) and in the QR on a
-- contact's statement PDF, only when that contact owes the user. Nullable, so
-- existing rows are unaffected. The CHECK matches Validators.optionalUpiId,
-- so the database rejects an ID that would build a broken pay link.
-- user_settings already has owner-only RLS; no policy change is needed.
--
-- Apply this before shipping the app version that sends upi_id, or settings
-- sync fails on the unknown column.

alter table public.user_settings
  add column upi_id text
    constraint user_settings_upi_id_check
    check (upi_id is null or upi_id ~ '^[a-zA-Z0-9._-]{2,256}@[a-zA-Z]{2,64}$');
