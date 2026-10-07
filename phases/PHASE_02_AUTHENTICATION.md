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

# Phase 02 — Authentication

## Objective
Implement complete Supabase authentication.

## Read
- docs/01_PRODUCT_REQUIREMENTS.md
- docs/02_ARCHITECTURE.md
- docs/04_SECURITY_RLS.md

## Tasks
- Splash
- Onboarding
- Register
- Login
- Logout
- Forgot password
- Reset password/deep link
- Change password
- Session restoration
- Auth guards
- Profile creation after signup
- Proper error states

## Acceptance
- New user can register.
- Existing user can login/logout.
- Session survives restart.
- Forgot/reset password works.
- Unauthorized users cannot access protected screens.
