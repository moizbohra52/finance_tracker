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

# Phase 10 — Profile and Settings

## Objective
Complete user-facing account and app configuration.

## Read
- docs/01_PRODUCT_REQUIREMENTS.md
- docs/06_UI_UX_GUIDELINES.md
- docs/04_SECURITY_RLS.md

## Tasks
- Profile view/edit
- Avatar
- Change password
- Currency
- Date format
- Number format
- Language foundation
- Theme settings
- Notification settings
- Default account
- About
- Privacy/terms placeholders
- Logout
- Delete account flow

## Acceptance
- Profile changes persist.
- Settings persist after restart.
- Password change works.
- Delete account is confirmed and secure.
