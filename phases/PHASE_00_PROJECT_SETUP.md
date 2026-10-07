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

# Phase 00 — Project Setup

## Objective
Create the Flutter project foundation and development conventions.

## Read
- docs/00_PROJECT_OVERVIEW.md
- docs/02_ARCHITECTURE.md
- docs/06_UI_UX_GUIDELINES.md
- docs/09_CODING_STANDARDS.md

## Tasks
- Initialize Flutter project.
- Configure package name/app name placeholders only if not already specified.
- Add core dependencies after checking current stable compatibility.
- Create folder architecture.
- Create AppRoutes and bindings skeleton.
- Create theme tokens and ThemeController.
- Create reusable AppButton, AppTextField, loading/error/empty components.
- Configure environment handling without committing secrets.
- Add lint/analyzer configuration.
- Add initial test structure.

## Acceptance
- Project builds.
- flutter analyze has no new errors.
- Light/dark theme works.
- Navigation skeleton works.
- Core widgets render.
