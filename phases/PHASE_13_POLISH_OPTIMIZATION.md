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

# Phase 13 — UI Polish and Performance

## Objective
Make the app production-grade.

## Read
- docs/06_UI_UX_GUIDELINES.md
- docs/09_CODING_STANDARDS.md

## Additional Design Reference
- docs/11_DESIGN_REFERENCE.md

## Tasks
- Remove unnecessary rebuilds
- Pagination everywhere needed
- Skeleton loading
- Empty/error/offline states
- Accessibility pass
- Keyboard/form UX
- Animation polish
- Dark theme audit
- Large data performance
- Memory/disposal audit
- Crash-safe error handling

## Acceptance
- No obvious jank on common devices.
- Large lists remain responsive.
- No analyzer warnings introduced.
- All major screens have polished states.
