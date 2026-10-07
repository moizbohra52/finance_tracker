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

# Phase 05 — Income and Expense

## Objective
Implement the main transaction engine.

## Read
- docs/03_DATABASE_SCHEMA.md
- docs/05_FINANCIAL_LOGIC.md
- docs/06_UI_UX_GUIDELINES.md

## Tasks
- Unified transaction model
- Add income
- Add expense
- Edit/delete transaction
- Categories
- Custom categories
- Payment method
- Notes
- Date/time
- Search/filter
- Pagination
- Monthly grouping
- Central BalanceCalculator
- Dashboard summary integration

## Acceptance
- Income increases account balance.
- Expense decreases account balance.
- Transactions persist and reload.
- Delete/update recalculates balance correctly.
- Pagination works.
