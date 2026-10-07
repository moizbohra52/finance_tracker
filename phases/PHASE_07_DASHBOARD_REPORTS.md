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

# Phase 07 — Dashboard and Reports

## Objective
Create useful financial analytics.

## Read
- docs/05_FINANCIAL_LOGIC.md
- docs/06_UI_UX_GUIDELINES.md

## Tasks
- Dashboard balance card
- Opening/current balance
- Today/month income
- Today/month expense
- Receivable/payable
- Recent transactions
- Monthly summary
- Income chart
- Expense chart
- Category analysis
- Account analysis
- Date range filters

## Acceptance
- Dashboard values match transaction data.
- Transfers are not double-counted.
- Report filters produce correct totals.
- Charts handle empty data.
