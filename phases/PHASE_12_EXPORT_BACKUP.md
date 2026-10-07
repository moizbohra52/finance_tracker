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

# Phase 12 — Export and Backup

## Objective
Provide data portability.

## Read
- docs/01_PRODUCT_REQUIREMENTS.md
- docs/02_ARCHITECTURE.md

## Tasks
- CSV export
- Excel export
- PDF report
- Date range selection
- Transaction/account/category filters
- Backup strategy
- Restore validation
- Share/save export

## Acceptance
- Export totals match app totals.
- Large exports do not freeze the UI.
- Imported/restored data is validated before replacing local data.
