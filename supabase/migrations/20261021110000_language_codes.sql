-- App language: English, Hindi, and Hindi in Latin script (Hinglish).
--
-- user_settings.language_code was limited to 'en' until more languages
-- existed (20261008120000_profile_settings.sql). 'hi-Latn' is the BCP 47 tag
-- for Hindi written in Latin letters. Existing rows are 'en' and stay valid.
--
-- Apply before shipping the app version with the language picker. Under the
-- old CHECK the app still shows Hindi or Hinglish at once, but the upload is
-- rejected; once sync gives up, the server's 'en' row is pulled back and
-- the language, with any other setting saved meanwhile, reverts.

alter table public.user_settings
  drop constraint user_settings_language_code_check,
  add constraint user_settings_language_code_check
    check (language_code in ('en', 'hi', 'hi-Latn'));
