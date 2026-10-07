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

# Phase 03 — Core Foundation

## Objective
Complete shared application infrastructure.

## Read
- docs/02_ARCHITECTURE.md
- docs/06_UI_UX_GUIDELINES.md
- docs/09_CODING_STANDARDS.md

## Additional Design Reference
- docs/11_DESIGN_REFERENCE.md

## Tasks
- App theme system
- Light/dark/system mode
- Accent color
- Storage service
- Network/connectivity service
- Error model
- Common widgets
- Route structure
- GetX bindings
- Date/currency/number utilities
- App constants
- Main shell/bottom navigation

## Acceptance
- App shell works after login.
- Theme persists after restart.
- Shared components are used by at least one real screen.
