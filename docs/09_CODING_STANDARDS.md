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
