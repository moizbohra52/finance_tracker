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

# Phase 11 — Offline First and Sync

## Objective
Add robust local data storage and Supabase synchronization.

## Read
- docs/07_OFFLINE_SYNC.md
- docs/05_FINANCIAL_LOGIC.md
- docs/09_CODING_STANDARDS.md

## Tasks
- Local relational database
- Local repositories
- Sync metadata
- Pending queue
- Upload sync
- Download sync
- Tombstones
- Retry/backoff
- Idempotency
- Conflict handling
- Sync status UI
- Connectivity handling

## Acceptance
- User can add transaction offline.
- Transaction appears locally immediately.
- Reconnection uploads exactly once.
- Data survives restart.
- Duplicate retry does not duplicate financial records.
