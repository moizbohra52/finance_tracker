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

## Implementation (Phase 09)

### Pieces
| Piece | Where | Job |
|---|---|---|
| `ReminderCalculator` | `domain/services/reminder_calculator.dart` | repeat maths, status, complete, snooze |
| `ReminderNotificationPlanner`, `NotificationIds` | `domain/services/reminder_notification_planner.dart` | reminders -> the exact set of device notifications, stable ids |
| `LocalNotificationService` | `core/services/local_notification_service.dart` | `flutter_local_notifications` wrapper (permission, schedule, cancel, show) |
| `PushService` | `core/services/push_service.dart` | FCM wrapper (token, foreground/opened/initial messages) |
| `NotificationCoordinator` | `core/services/notification_coordinator.dart` | preferences, permission state, sync, raise-once, tap routing, token registration |
| `NotificationTarget` | `features/notifications/notification_target.dart` | payload / push data -> route |
| `ReminderController` | `features/reminders/` | reminder CRUD, complete, snooze, enable/disable |
| `NotificationCenterController` | `features/notifications/` | stored notifications, unread badge, mark read |

### Scheduling
- Reminders are loaded by `ReminderController`; every load hands them to
  `NotificationCoordinator.syncReminders`, which replaces the device schedule
  with the planner's output. IDs are `FNV-1a("reminder:<uuid>")` folded to 31
  bits (stable across runs, pinned by a test), so scheduling an existing
  reminder replaces its entry; entries not in the plan are cancelled. Overlapping
  syncs are folded into one more pass. This is the duplicate-prevention
  mechanism: there is no "schedule" call that can be repeated, only "make the
  device match this list".
- The shell creates `ReminderController` when it opens, so the schedule is
  restored on every launch without visiting the reminders screen. It is also
  re-applied when the app resumes (time-zone or permission changes) and the
  OS restores scheduled notifications after a reboot (boot receiver).
- Repeating reminders are scheduled at their next occurrence with an OS-level
  repeat (`daily` -> time, `weekly` -> day of week + time, `monthly` -> day of
  month + time, `yearly` -> date + time), so they keep firing while the app is
  closed. **Limit:** for monthly/yearly reminders on the 29th-31st (29 Feb) the
  OS repeat follows the platform rule and may skip short months; the app
  recomputes the exact month-end-clamped date every time it opens.
- **Late delivery.** Android delivers inexact alarms late (about 30 s here,
  up to ~15 min in Doze). A notification that came due within the last 15
  minutes (`ReminderCalculator.deliveryGrace`) is *in flight*: a resync, for
  example when the app is reopened, neither cancels nor replaces its pending
  alarm. Without this, reopening the app between the due time and the delivery
  replaced today's alarm with tomorrow's and the notification was lost
  (found on an Android 17 emulator). After the grace period the reminder
  rolls to its next occurrence as usual.
- A snooze is a one-off notification at the snooze time; the series resumes
  after the reminder is completed or the app next syncs.
- A one-time reminder whose time has passed is *overdue*: it is listed as
  overdue, recorded once in the notification center, and not scheduled.
- iOS keeps at most 64 pending local notifications; the planner schedules the
  60 soonest.
- Android: exact alarms need `SCHEDULE_EXACT_ALARM`, which Android 14+ does not
  grant by default. Without it reminders use inexact alarms (can be minutes
  late); Settings > Notifications shows an "Exact reminder times" row that
  opens the system screen. `USE_EXACT_ALARM` was not used: Google Play limits
  it to alarm/calendar apps.

### Permission
`NotificationPermissionState`: `granted`, `denied` (not allowed, may still
prompt), `blocked` (not allowed after the app already asked: settings only),
`unsupported` (web/desktop), `unknown`.
- Nothing is asked at startup. The system prompt appears (a) the first time a
  reminder with notifications on is saved, or (b) when the user turns
  notifications on in Settings. The app asks at most once; afterwards the state
  is `blocked` and the UI offers **Open settings** instead of prompting.
- A passive banner (not a dialog) on the reminder screens, the notification
  center and Settings explains the state and offers the one fix: *Turn on*
  (master switch off), *Allow* (can prompt) or *Open settings* (blocked).
- State is re-read when the app resumes, so granting in system settings takes
  effect immediately.

### Preferences (device-local, `StorageService`)
Notifications (master), Reminders, Budget alerts, Recurring transactions,
Sound, Vibration. They are per device because sound, vibration and permission
are. The server column `user_settings.notifications_enabled` is not used yet
(Phase 10 owns synced settings). Vibration is hidden on iOS, where the OS
decides. Android fixes sound/vibration per channel at creation, so each
on/off combination has its own channel id (`reminders_sv`, `alerts_qn`, ...).
Budget and recurring alerts that are switched off are not raised at all; they
are raised when switched back on if still relevant.

### What a notification may contain
Title = what the user typed as the reminder title; body = a generic line for
the type ("Money to collect"). **Amounts and contact names never appear** in a
notification, the default reminder titles contain neither, and Android shows
the content as private on a secure lock screen. The notification center, which
is behind sign-in, shows the full text.

### Deep links
Local payload: `<type>:<id>` (`reminder:<uuid>`). Push data: `type` and
`reference_id`. Both go through `NotificationTarget.resolve`:

| type | opens |
|---|---|
| `reminder` | reminder detail (complete / snooze / edit / open contact) |
| `budget_alert`, `budget` | budgets |
| `recurring` | recurring transactions |
| `contact`, `khata` | contact detail |
| `transaction` | transaction detail |
| anything else, or a missing/invalid id | notification center |

Ids are validated as UUIDs before use because push data comes from outside the
app. A tap that arrives before the signed-in shell is on screen (cold start,
signed out) is held and opened once the shell mounts; sign-out discards it.

### Push (FCM)
- Client only. `PushService.initialize` calls `Firebase.initializeApp()`; with
  no Firebase config it reports unavailable, logs the exception *type*, and the
  app carries on (local reminders do not depend on it).
- Token: registered to `device_tokens` (upsert on `user_id, device_id`) after
  sign-in, on token refresh and when permission is granted; the row is
  deactivated and the FCM token deleted *before* sign-out
  (`AuthRepository.beforeSignOut`), so the next user on the device cannot
  receive this user's pushes. Tokens are never logged.
- Foreground: FCM shows nothing, so the message is shown as a local notification.
  Background: the OS shows messages that have a `notification` block; the tap
  arrives on `onMessageOpenedApp`. Terminated: the launching tap is read with
  `getInitialMessage`. **Data-only messages are not supported.**
- **Sender contract** (not implemented in this phase): a server (for example a
  Supabase Edge Function using the FCM HTTP v1 API with a service account kept
  in Supabase secrets) sends to `device_tokens` rows where `active`, with a
  `notification` block containing a generic title/body and
  `data: {type, reference_id}`, `android.notification.channel_id = alerts_sv`.
  No sender exists yet, so no remote pushes are delivered today.

### Firebase setup (one time per environment)
1. Create a Firebase project; add Android app `com.finance_tracker.app` and an
   iOS app with the bundle id from Xcode.
2. Put `google-services.json` in `android/app/` and `GoogleService-Info.plist`
   in `ios/Runner/` (both are gitignored; the Gradle plugin is applied only
   when the Android file exists).
3. iOS: enable the Push Notifications and Background Modes > Remote
   notifications capabilities in Xcode and upload an APNs key to Firebase.
4. Never place FCM server credentials or the Supabase service-role key in the app.

### Not in this phase
Notification action buttons (Done / Snooze from the notification), the FCM
sender, a notification-center delete, and synced notification settings.
