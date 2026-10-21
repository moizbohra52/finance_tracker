# Coding Standards

## Dart
- sound null safety
- format with dart format
- analyze with flutter analyze
- meaningful names
- avoid abbreviations
- prefer final
- const wherever possible

## Naming
Classes: PascalCase
Variables/functions: camelCase
Files: snake_case
Constants: lowerCamelCase or project convention

## Controllers
A controller should not become a dumping ground.
Split large features into focused controllers/services.

## Models
Prefer immutable models where practical.
Implement serialization explicitly.

## Repository
Repository interfaces should not expose UI concerns.

## Error handling
Never use empty catch blocks.
Log developer diagnostics safely.
Expose user-friendly messages.

## Widgets
- small
- reusable
- testable
- avoid deeply nested build methods

## User-visible text
- Write it in English and wrap it: `'Settings'.tr`. The English text is the
  key; `lib/core/translations/hindi.dart` and `hinglish.dart` hold the
  Hindi and Hinglish text, and every key needs an entry in both.
- Values go in params, never in the key: `'@count accounts'.trParams(
  {'count': '$n'})`, not `'$n accounts'.tr`.
- Translate where the text is built, inside `build` or a getter, not in a
  `static` or `const` value: those are fixed before the language changes.
- A screen whose text is translated is listed in `translatedFiles`
  (`test/core/translations/translation_coverage_test.dart`); that test
  fails on an untranslated literal or a missing key.

## State
Use Rx only where reactivity is needed.
Dispose resources properly.

## Database
No raw SQL scattered throughout Flutter.
Centralize queries/data sources.

## Comments
Comment why, not obvious what.
Document accounting rules and tricky synchronization logic.

## Dependencies
Before adding a package:
- confirm it is maintained
- confirm Flutter compatibility
- check whether existing packages can solve the need
- document why it is needed

## Git
Use focused commits:
feat(auth): ...
fix(balance): ...
refactor(sync): ...
docs(database): ...

Never commit generated secrets.
