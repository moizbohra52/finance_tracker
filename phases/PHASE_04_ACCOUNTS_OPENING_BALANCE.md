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

# Phase 04 — Accounts and Opening Balance

## Objective
Implement financial accounts and opening balances.

## Read
- docs/03_DATABASE_SCHEMA.md
- docs/05_FINANCIAL_LOGIC.md

## Tasks
- Account list
- Add/edit/archive account
- Account detail
- Cash/bank/UPI/card/other types
- Opening balance
- Opening balance date
- Account balance calculation
- Account transaction list
- Default account
- Validation

## Acceptance
- User can create multiple accounts.
- Opening balance appears correctly.
- Account balances update after transactions.
- Archived accounts are not selectable for new transactions.
