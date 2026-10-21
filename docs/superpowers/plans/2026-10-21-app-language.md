# App Language (part 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** English / हिंदी / Hinglish chosen in Settings, saved to the account, applied to the shell, Dashboard and Settings at once; untranslated screens stay English.

**Architecture:** GetX `Translations` keyed by the English text (`'Settings'.tr`); Hindi (`hi_IN`) and Hinglish (`hi_Latn`) maps only. `AppLanguage` is a preference like `DateStyle`, stored as `en`/`hi`/`hi-Latn` in `user_settings.language_code`; `SettingsController._apply` calls `Get.updateLocale`. Dates format in `hi_IN` for Hindi.

**Tech Stack:** Flutter, GetX 4 (`Translations`, `.tr`, `.trParams`, `Get.updateLocale`), intl `DateFormat`.

**Spec:** `docs/superpowers/specs/2026-10-21-app-language-design.md`

## Global Constraints
- Stored codes exactly `en`, `hi`, `hi-Latn`; unknown/null → English.
- GetX translation map keys exactly `hi_IN` and `hi_Latn`; English has no map.
- `AppLanguage` values: `english('en', 'English', Locale('en', 'IN'), 'en_IN')`, `hindi('hi', 'हिंदी', Locale('hi', 'IN'), 'hi_IN')`, `hinglish('hi-Latn', 'Hinglish', Locale('hi', 'Latn'), 'en_IN')`.
- Strings with values use `.trParams({'name': value})` with `@name` in the key; never `.tr` on an interpolated string.
- Language names in the picker are not translated.
- No new packages. Do not commit; the user commits. The user applies Supabase SQL by hand.
- Each task ends with `flutter analyze` clean and its tests green; the whole suite keeps exactly the 28 pre-existing failures.

## Review Focus
1. Switching language while screens are open changes them at once, without restart — Task 2 flow test `choosing Hindi changes the open screens`.
2. Signing out (or another account taking over) returns to English, so the next user does not inherit Hindi — Task 1 test `reset at sign-out returns to English`.
3. A string with an interpolated value wrapped in `.tr` can never match a key — Task 3 test `no interpolated string is translated with .tr`.
4. Saving Hindi before the migration is applied (server CHECK rejects it) keeps the previous language and shows the save error — Task 1 test `a rejected language keeps the previous one`.
5. A key used in a translated screen but missing from one map silently shows English — Task 3 test `every key used in part 1 screens is in both maps`.

---

### Task 1: `AppLanguage` preference, locale switching, date locale, migration

**Files:**
- Modify: `lib/domain/entities/user_preferences.dart` (add `AppLanguage`; `languageCode` → `language`)
- Modify: `lib/features/settings/controllers/settings_controller.dart` (map to/from `UserSettings.languageCode`; `_apply` calls `Get.updateLocale` when it differs from `Get.locale`)
- Modify: `lib/core/utils/app_formatters.dart:49-65` (`locale` params become `String?`, default `preferences.language.dateLocale`)
- Modify: `lib/main.dart:40` (also `initializeDateFormatting('hi_IN')`), `test/helpers/fakes.dart` `pumpApp` (same)
- Create: `supabase/migrations/20261021110000_language_codes.sql`; Modify `docs/03_DATABASE_SCHEMA.md` (migration 11)
- Test: `test/features/settings/settings_language_test.dart`

**Interfaces:**
- Produces: `enum AppLanguage { english, hindi, hinglish }` with `final String stored; final String label; final Locale locale; final String dateLocale; static AppLanguage fromStored(String?)`; `UserPreferences.language` (default `AppLanguage.english`), `copyWith({AppLanguage? language})`.

- [ ] **Step 1: Write the failing tests**

```dart
test('stored codes map to languages, anything else is English', () {
  expect(AppLanguage.fromStored('hi'), AppLanguage.hindi);
  expect(AppLanguage.fromStored('hi-Latn'), AppLanguage.hinglish);
  expect(AppLanguage.fromStored('en'), AppLanguage.english);
  expect(AppLanguage.fromStored('fr'), AppLanguage.english);
  expect(AppLanguage.fromStored(null), AppLanguage.english);
});
test('a saved Hindi account loads in Hindi', ...);
  // userSettings.settings languageCode 'hi' → load()
  // expect(controller.preferences.value.language, AppLanguage.hindi); expect(Get.locale, const Locale('hi', 'IN'))
test('saving Hinglish writes hi-Latn', ...);
  // expect(userSettings.writes.single.languageCode, 'hi-Latn'); expect(Get.locale, const Locale('hi', 'Latn'))
test('a rejected language keeps the previous one', ...);
  // userSettings fails the write (FakeUserSettingsRepository.nextError / failing write) → savePreferences(hindi) is false
  // expect(controller.preferences.value.language, AppLanguage.english)
test('reset at sign-out returns to English', ...);
  // after loading 'hi', controller.reset() → language english, Get.locale en_IN
test('Hindi dates use Hindi month names', () {
  AppFormatters.preferences = const UserPreferences(language: AppLanguage.hindi);
  expect(AppFormatters.date(DateTime(2026, 10, 8), pattern: 'd MMMM y'), '8 अक्टूबर 2026');
});
```
(Tests run under `Get.testMode = true`; `initializeDateFormatting('hi_IN')` in `setUpAll`; `tearDown` resets `AppFormatters.preferences` and `Get.locale`.)

- [ ] **Step 2: Run** `flutter test test/features/settings/settings_language_test.dart` — FAIL (no `AppLanguage`).
- [ ] **Step 3: Implement.** Replace every `languageCode` use of `UserPreferences` (grep `languageCode` under `lib/` and `test/`). Migration: `alter table public.user_settings drop constraint user_settings_language_code_check, add constraint user_settings_language_code_check check (language_code in ('en', 'hi', 'hi-Latn'));` with a header comment saying to apply before shipping.
- [ ] **Step 4: Run** the test file and `flutter test test/features/settings test/core/utils` — new tests pass; only pre-existing failures remain (settings_flow has 1).

### Task 2: Translations, the Settings language picker, translated shell

**Files:**
- Create: `lib/core/translations/app_translations.dart` (`class AppTranslations extends Translations { Map<String, Map<String, String>> get keys => {'hi_IN': hindi, 'hi_Latn': hinglish}; }`), `lib/core/translations/hindi.dart` (`const Map<String, String> hindi`), `lib/core/translations/hinglish.dart` (`const Map<String, String> hinglish`)
- Modify: `lib/main.dart` `GetMaterialApp` (`translations: AppTranslations()`, `locale:` and `fallbackLocale: AppLanguage.english.locale`)
- Modify: `lib/features/settings/views/settings_view.dart` (Language tile → `showChoiceSheet<AppLanguage>`, `value: prefs.language.label`, subtitle removed)
- Modify: `lib/features/dashboard/views/app_shell_view.dart` (navigation labels, FAB labels, tooltips, semantics labels → `.tr`)
- Test: `test/core/translations/translation_maps_test.dart`, `test/features/settings/language_flow_test.dart`

**Interfaces:**
- Consumes: Task 1 `AppLanguage`, `UserPreferences.language`.
- Produces: `hindi` and `hinglish` maps every later task adds to.

- [ ] **Step 1: Write the failing tests**

```dart
// translation_maps_test.dart
test('both maps have the same keys and no empty text', () {
  expect(hindi.keys.toSet(), hinglish.keys.toSet());
  expect(hindi.values.where((String v) => v.trim().isEmpty), isEmpty);
  expect(hinglish.values.where((String v) => v.trim().isEmpty), isEmpty);
});
test('every @param of a key is kept in its translations', () {
  // for each key, RegExp(r'@\w+') matches of the key ⊆ matches of hindi[key] and hinglish[key]
});

// language_flow_test.dart (pumpApp, signed in)
testWidgets('choosing Hindi changes the open screens', ...);
  // Settings tab → tap 'Language' tile → tap 'हिंदी' in the sheet
  // expect(find.text(hindi['Settings']!), findsWidgets) and the navigation label hindi['Home']! (whatever the shell's first label is)
  // expect(userSettings.writes.last.languageCode, 'hi')
testWidgets('English stays English', ...);
  // default account: navigation labels are the English keys
```

- [ ] **Step 2: Run** both files — FAIL (no maps / no picker).
- [ ] **Step 3: Implement** the classes, wiring and picker; translate the shell strings and add their Hindi and Hinglish entries.
- [ ] **Step 4: Run** both files plus `flutter test test/features/settings test/app_test.dart` — new tests pass; only pre-existing failures remain.

### Task 3: Translate Dashboard and Settings; guard tests; coding standard

**Files:**
- Modify: `lib/features/dashboard/views/dashboard_view.dart`, `lib/features/settings/views/settings_view.dart`, `lib/features/settings/widgets/settings_widgets.dart`, `lib/features/notifications/widgets/notification_settings_section.dart`, `lib/features/app_lock/widgets/app_lock_tile.dart`, `lib/features/auth/widgets/account_switcher_sheet.dart` (switch account tile), `lib/features/auth/widgets/confirm_sign_out.dart`
- Modify: `lib/core/translations/hindi.dart`, `hinglish.dart`
- Modify: `docs/09_CODING_STANDARDS.md` (user-visible text: English, `.tr` / `.trParams`, entry in both maps)
- Test: `test/core/translations/translation_coverage_test.dart`

**Interfaces:**
- Consumes: Task 2 maps.
- Produces: `const List<String> translatedFiles` in the test (the part-1 files above plus `app_shell_view.dart`), which later parts extend.

- [ ] **Step 1: Write the failing tests** (read each file in `translatedFiles` with `File(...).readAsStringSync()`):

```dart
test('every key used in part 1 screens is in both maps', ...);
  // keys = RegExp(r"'((?:[^'\\]|\\.)*)'\s*\.\s*tr(?:Params)?\b") matches (also the "..." form)
  // every key must be in hindi and hinglish; failure message lists the missing keys
test('no interpolated string is translated with .tr', ...);
  // no match of RegExp(r"'[^']*\$[^']*'\s*\.\s*tr\b") in those files
test('part 1 screens have no untranslated Text literal', ...);
  // no match of RegExp(r"Text\(\s*'[^']+'\s*[,)]") in those files (a Text literal must go through .tr)
```

- [ ] **Step 2: Run** `flutter test test/core/translations` — FAIL (literals not wrapped yet).
- [ ] **Step 3: Implement.** Wrap every user-visible literal in those files (Text, labels, titles, subtitles, tooltips, snackbars, dialog texts) with `.tr` / `.trParams` and add Hindi and Hinglish entries. Drop `const` only where `.tr` requires it. Values computed elsewhere (amounts, names, dates) are not keys.
- [ ] **Step 4: Run** `flutter test test/core/translations test/features/settings test/features/reports test/app_test.dart`, then the whole suite and `flutter analyze` — clean analyzer; exactly the 28 pre-existing failures (diffed against the last full run).
