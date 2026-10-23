# App language (English, Hindi, Hinglish) — design, part 1

Date: 2026-10-21. Status: approved in chat, awaiting spec review.

## Goal
Let the user read the app in English, Hindi (Devanagari) or Hinglish (Hindi in
Roman letters). Part 1 builds the language system and translates the screens
seen most: the app shell, Dashboard and Settings. Later parts translate the
remaining screens in batches on the same system, each on its own.

Success: in Settings → Language the user picks हिंदी or Hinglish, and the bottom
navigation, Dashboard and Settings change at once, dates show in that
language, the choice is saved to the account and comes back after restart and
on another device. Screens not yet translated keep showing English.

## Decisions
- Approach: GetX `Translations`, with the English text itself as the key
  (`'Settings'.tr`). Only Hindi and Hinglish maps exist; a missing key shows
  the English key, which is the fallback for untranslated screens.
- Stored values in `user_settings.language_code`: `en`, `hi`, `hi-Latn`
  (BCP 47 tag for Hindi in Latin script). Unknown or null → English.
- GetX locales: English `en_IN`, Hindi `hi_IN`, Hinglish `hi_Latn` (map keys of
  `AppTranslations.keys`).
- Date formatting locale: `en_IN` for English and Hinglish, `hi_IN` for Hindi.
  Number grouping and currency stay as the number/currency settings say.
- The language is an account preference (like the others): applied when the
  preferences load after sign-in, English again after sign-out. Sign-in and
  sign-up screens stay English.
- Strings with values use GetX params: `'@count changes'.trParams({...})`.
- Translations are written by the implementer; a native speaker should review
  them before release.
- Out of scope for part 1: all screens other than shell, Dashboard and
  Settings; error messages from repositories and validators; notification and
  reminder texts; PDF/CSV export (PDF needs a Devanagari font: separate work).

## Schema
New migration `supabase/migrations/20261021110000_language_codes.sql`:
replace `user_settings_language_code_check` with
`check (language_code in ('en', 'hi', 'hi-Latn'))`. No new column; RLS
unchanged. Apply before shipping: saving Hindi fails the server CHECK
otherwise (the local value still applies on this device).

## Components
- `AppLanguage` enum in `lib/domain/entities/user_preferences.dart`, like
  `DateStyle`: `english('en', 'English', Locale('en', 'IN'), 'en_IN')`,
  `hindi('hi', 'हिंदी', Locale('hi', 'IN'), 'hi_IN')`,
  `hinglish('hi-Latn', 'Hinglish', Locale('hi', 'Latn'), 'en_IN')`;
  `fromStored(String?)` falls back to `english`.
  `UserPreferences.languageCode` (String) becomes `language` (AppLanguage);
  `SettingsController` maps it to and from `UserSettings.languageCode`.
- `lib/core/translations/app_translations.dart`: `AppTranslations extends
  Translations` returning `{'hi_IN': hindi, 'hi_Latn': hinglish}`; the maps live
  in `hindi.dart` and `hinglish.dart` in the same folder.
- `GetMaterialApp` (`lib/main.dart`): `translations: AppTranslations()`,
  `locale: AppLanguage.english.locale`, `fallbackLocale:
  AppLanguage.english.locale`.
- `SettingsController._apply` calls `Get.updateLocale(next.language.locale)`
  when the language differs from `Get.locale`.
- `AppFormatters.date`/`dateTime`/`dayLabel` default their `locale` to
  `preferences.language.dateLocale` instead of `AppConstants.defaultLocale`.
  `main.dart` initializes date symbols for `hi_IN` as well as `en_IN`.
- Settings → Language: a `SettingsTile` showing the language's own name, opening
  `showChoiceSheet<AppLanguage>`; the "More languages are coming" subtitle goes.
- Translated in part 1 (every user-visible literal, wrapped in `.tr` /
  `.trParams`): `app_shell_view.dart` (navigation labels, tooltips),
  `dashboard_view.dart`, `settings_view.dart`, `settings_widgets.dart`,
  `notification_settings_section.dart`, `app_lock_tile.dart`, the switch
  account tile and sign-out confirmation reached from Settings.
- Language names in the picker are not translated (each in its own script).

## Error handling
- An unknown stored code shows English (no crash).
- A failed save keeps the previous language and shows the existing save error
  (same path as the other preferences).

## Testing
- `AppLanguage.fromStored`: `en`/`hi`/`hi-Latn`, unknown → English.
- `SettingsController`: loading `hi` sets `preferences.language` and
  `Get.locale` to `hi_IN`; saving Hinglish writes `hi-Latn`; reset at sign-out
  returns to English.
- `AppFormatters.date` with Hindi gives Hindi month names
  (`8 अक्टूबर 2026` for `d MMMM y`).
- Translation maps: the Hindi and Hinglish maps have exactly the same keys, no
  empty values, and every `@param` in a key appears in its translations.
- Flow test: Settings → Language → हिंदी, then the bottom navigation shows the
  Hindi labels; existing English tests keep passing unchanged.

## Docs
- `docs/03_DATABASE_SCHEMA.md`: migration 11 (language codes).
- `docs/09_CODING_STANDARDS.md`: user-visible text is written in English and
  wrapped in `.tr` (params with `.trParams`), with entries in both maps.

## Final scope (after parts 1-4, B and C)
- Every screen, error message and notification text follows the language.
- This device remembers the last language (`StorageService.readLanguage`,
  key `app.language`). The app starts in it, the signed-out screens (splash,
  onboarding, sign in, sign up, password reset) and the app lock screen use it,
  and a language button on onboarding and the auth forms changes it. Sign-out
  and an account switch keep it; the next account's own language replaces it
  once its settings load. An account whose language is unknown keeps the
  device's.
- A new account starts in the language shown at sign-up: the app sends
  `language_code` in the signup metadata and the signup trigger stores it
  (`20261023090000_signup_language.sql`).
- Scheduled reminder notifications hold their text in the OS, so a language
  change schedules them again (`NotificationCoordinator.languageChanged`).
  The buttons' background isolate loads the saved language
  (`AppTranslations.use`). Notification-center entries are stored in the
  language of the moment they were made. Android channel names are fixed when
  the channel is first created. Only the signed-in account's scheduled
  reminders are rewritten on a language change; another signed-in account's
  follow when it becomes active. Server push text is not ours.
- **PDF stays English.** Spike: the `pdf` package (3.12) has no OpenType
  shaping, so Noto Sans Devanagari renders matras on the wrong side
  (`किताब` as `कतिाब`) and conjuncts with a visible halant (`क्ष` as `क्‌ष`).
  Broken Hindi in a statement given to a customer is worse than English.
  Revisit with a package that shapes Devanagari, or a PDF built by the
  platform's text engine. The same limit means Hindi text typed by the user
  (names, notes) does not print correctly in a PDF either.
