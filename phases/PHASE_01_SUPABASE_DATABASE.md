# Claude Phase Execution Rules

Before starting:
1. Read `/CLAUDE.md`.
2. Read all docs referenced below.
3. Inspect the current repository and do not assume files exist.
4. Reuse existing working code.
5. Implement only this phase unless a dependency is genuinely required.
6. Run formatting, analyzer and relevant tests.
7. Update documentation if implementation decisions differ from the spec.
8. At the end, report:
   - files created/changed
   - database changes
   - packages added
   - tests run
   - known issues
   - acceptance criteria status

Never use pseudo-code for implementation.
Never replace working files wholesale without first inspecting them.

# Phase 01 — Supabase Database

## Objective
Implement the PostgreSQL schema and security foundation.

## Read
- docs/03_DATABASE_SCHEMA.md
- docs/04_SECURITY_RLS.md
- docs/05_FINANCIAL_LOGIC.md

## Tasks
- Create ordered SQL migrations.
- Create profiles, settings, accounts, categories, transactions, contacts, contact_transactions, budgets, recurring_transactions, reminders, notifications.
- Add indexes, constraints and timestamps.
- Add RLS policies.
- Add profile creation trigger/function if appropriate.
- Seed system categories safely.
- Document migration order.
- Test cross-user isolation.

## Acceptance
- Migrations run on a fresh Supabase project.
- All user-owned tables have RLS.
- Cross-user read/write is denied.
- Foreign keys and monetary types are correct.
