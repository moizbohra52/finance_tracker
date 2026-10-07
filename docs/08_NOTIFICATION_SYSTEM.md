# Notification System

## Technologies
- Firebase Cloud Messaging for remote push
- flutter_local_notifications (or current equivalent) for local scheduled notifications

## Notification types
- payment due
- receivable due
- payable due
- budget 75/90/100
- recurring transaction due
- custom reminder
- security/account events

## Device token
Store FCM device tokens per user/device in a dedicated table if server push is used.

Recommended fields:
- id
- user_id
- token
- platform
- device_id
- active
- updated_at

## Local notifications
Schedule on-device reminders for predictable local events.
Handle:
- timezone changes
- app reinstall
- permission denial
- duplicate schedules

## Push
Supabase Edge Functions/server backend may trigger FCM where server-side delivery is required.

Never put FCM server credentials in Flutter.

## Notification center
Persist important notifications in Supabase so they can appear across devices.

## Permissions
Ask notification permission at a sensible onboarding point, not immediately on first frame.

## Deep links
Notification taps should open:
- reminder
- contact
- transaction
- budget
where applicable.

## Reliability
Notification creation must be idempotent when generated from recurring/budget rules.
