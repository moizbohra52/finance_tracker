# Finance Tracker / Digital Khata — Claude Project Instructions

## Project Goal
Build a production-ready Flutter personal finance and digital khata application combining:
- Personal income and expense tracking
- Cash/bank/UPI account management
- Opening and closing balances
- Credit/debit ledger (khata)
- Receivables/payables
- Budgets
- Recurring transactions
- Reminders
- Push/local notifications
- Reports and analytics
- Offline-first local caching and Supabase synchronization
- Profile, settings, themes, backup and export

## Technology
- Flutter + Dart, null safety
- GetX for state management, routing and dependency injection
- Supabase Auth + PostgreSQL + RLS
- Local storage for preferences/session
- Drift/SQLite or another robust local database for offline transaction data
- Firebase Cloud Messaging + local notifications
- Charts and export packages only when justified

## Non-negotiable Engineering Rules
1. Never put Supabase queries directly in UI widgets.
2. Never put business/accounting calculations in widgets.
3. Use feature-based architecture.
4. Use GetX Controllers only for presentation/application state; repositories own data access.
5. Keep financial calculations in one centralized domain/service layer.
6. Every user-owned Supabase table must be protected by RLS.
7. Never ship a Supabase service-role key in Flutter.
8. Use UUIDs generated client-side where offline creation is required.
9. All transaction writes must be idempotent and sync-safe.
10. Do not silently change existing architecture while implementing a phase.
11. Preserve working functionality when modifying code.
12. Do not invent fields, APIs, tables, or packages without documenting the decision.
13. Prefer small reusable widgets and services.
14. Use const constructors and avoid unnecessary rebuilds.
15. Handle loading, success, empty, error and offline states.
16. Use pagination for large lists.
17. Destructive operations require confirmation.
18. Never log passwords, access tokens, financial secrets, or sensitive personal data.
19. Do not use pseudo-code in production implementation.
20. Before changing database schema, update the relevant documentation and migration.

## Claude Workflow
Before coding a phase:
1. Read CLAUDE.md.
2. Read the phase file.
3. Read all referenced docs.
4. Inspect the existing repository before changing files.
5. State a concise implementation plan.
6. Implement only the requested phase.
7. Run formatter/analyzer/tests relevant to the changes.
8. Report changed files, validation results, and any blockers.

Do not start a later phase until the current phase passes its acceptance criteria unless the user explicitly asks.

## Documentation Source of Truth
- Product scope: docs/01_PRODUCT_REQUIREMENTS.md
- Architecture: docs/02_ARCHITECTURE.md
- Database: docs/03_DATABASE_SCHEMA.md
- Security: docs/04_SECURITY_RLS.md
- Financial rules: docs/05_FINANCIAL_LOGIC.md
- UI/UX: docs/06_UI_UX_GUIDELINES.md
- Offline sync: docs/07_OFFLINE_SYNC.md
- Notifications: docs/08_NOTIFICATION_SYSTEM.md
- Coding: docs/09_CODING_STANDARDS.md
- Testing: docs/10_TESTING_STRATEGY.md

## Definition of Done
A phase is complete only when:
- requested functionality is implemented;
- no known analyzer errors remain;
- relevant tests pass;
- loading/error/empty/offline states are handled;
- database/security changes are documented;
- no unrelated regressions are introduced;
- acceptance criteria in the phase file are satisfied.
