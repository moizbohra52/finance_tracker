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

# Phase 06 — Digital Khata

## Objective
Implement contact ledger, credit/debit and settlement.

## Read
- docs/03_DATABASE_SCHEMA.md
- docs/05_FINANCIAL_LOGIC.md

## Tasks
- Contact list
- Add/edit contact
- Opening receivable/payable
- Add credit
- Add debit
- Receive payment
- Make payment
- Contact detail timeline
- Outstanding balance
- Search/filter
- Due date
- Settlement validation
- Reminder entry point

## Acceptance
- Receivable/payable direction is unambiguous.
- Settlement reduces outstanding balance.
- Contact balances survive app restart.
- Invalid settlement is rejected.
