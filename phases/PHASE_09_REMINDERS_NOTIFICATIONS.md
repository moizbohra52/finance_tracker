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

# Phase 09 — Reminders and Notifications

## Objective
Implement local and push notification infrastructure.

## Read
- docs/07_OFFLINE_SYNC.md
- docs/08_NOTIFICATION_SYSTEM.md
- docs/04_SECURITY_RLS.md

## Tasks
- Notification permission flow
- FCM setup
- Device token registration
- Local notification scheduling
- Reminder CRUD
- Repeat rules
- Notification center
- Mark read
- Deep links
- Budget notifications
- Payment notifications
- Recurring notifications

## Acceptance
- User can create a reminder.
- Notification fires at expected local time.
- Notification tap opens correct feature.
- Duplicate notification scheduling is prevented.
