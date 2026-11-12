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
- **The OS repeat ignores the date it is given** (Android
  `getNextFireDateMatchingDateTimeComponents`, iOS calendar triggers): it fires
  at the first matching time *after now*. So the planner uses it only when that
  first match is the planned date. Otherwise (a repeating reminder marked done
  before today's time, a weekly/monthly series that starts later) the next
  occurrence is a one-shot, and the series switches back to the OS repeat at
  the next sync. Before 2026-10-19 the OS repeat was always used, so "Mark
  done" early still fired that day. **Limit:** if the app is not opened between
  that one-shot and the occurrence after it, the later one is missed.
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

### Notification buttons (Android, 2026-10-19)
Reminder notifications carry **Mark done** and **Snooze 1 hour**
(`ReminderAction`; the enum name is the action id the OS hands back). Tapping
one clears the notification without opening the app.
- The plugin calls `reminderActionInBackground`
  (`core/services/reminder_action_handler.dart`) in a background isolate, even
  while the app is open, so it uses no GetX service. It opens the account's
  own database file named in the payload (only if it exists: never creates
  one) on a separate connection (`singleInstance: false`; sqflite shares single
  instances across isolates), applies `ReminderCalculator.applyAction` (the
  same as Mark done / a one-hour snooze in the app) and saves through
  `ReminderRepository.update`, which queues the sync like any edit.
- Then it reschedules only that reminder (`replaceSchedule` with `owns`
  limited to its payload), using the device preferences re-read from storage.
- If the app is running it is told through an `IsolateNameServer` port
  (`listenForReminderActions` in `main.dart`): `DataChangeNotifier` reloads the
  screens and `SyncEngine.notifyNewQueueItem` sends the change. Otherwise the
  change is picked up and synced at the next launch.
- A deleted or already completed reminder is left alone. A failed write is
  logged (type only); the notification is already gone, the reminder unchanged.
- The buttons work on a locked phone without the app lock. Android hides
  actions of `private` notifications on a secure lock screen.
- iOS: not wired (needs a Darwin category and background plugin registration
  in `AppDelegate`), so iOS notifications have no buttons.

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
Local payload: `<user id>|<type>:<id>` (`<uuid>|reminder:<uuid>`); payloads
from before 2026-10-15 have no `<user id>|` and belong to the active account.
Push data: `type`, `reference_id` and `user_id`. Both go through
`NotificationTarget.resolve`:

| type | opens |
|---|---|
| `reminder` | reminder detail (complete / snooze / edit / open contact) |
| `budget_alert`, `budget` | budgets |
| `recurring` | recurring transactions |
| `contact`, `khata` | contact detail |
| `transaction` | transaction detail |
| `loan` | loan payment form (the loan's) |
| anything else, or a missing/invalid id | notification center |

Ids are validated as UUIDs before use because push data comes from outside the
app. A tap that arrives before the signed-in shell is on screen (cold start,
signed out, switching accounts) is held and opened once the shell mounts;
sign-out discards it.

### Several signed-in accounts (2026-10-15)
- Every notification carries the account it is for: local payloads are
  prefixed with the user id, and on Android the notification's `tag` is the
  user id (Android does not return payloads of shown notifications).
- Tapping a notification of another account that is signed in on the device
  switches to that account first, then opens the target, and says "Switched
  to <name>". This also works from a cold start. A notification of an account
  that is not signed in here opens nothing and says so.
- Reminders scheduled while an account was active stay scheduled while
  another account is active: `replaceSchedule` only replaces the active
  account's entries. They reflect that account's reminders as they were when
  it was last active. On iOS the 64-pending limit is shared by all accounts.
- Signing one account out cancels only its scheduled and shown notifications
  and deactivates only its `device_tokens` row; the FCM token is deleted only
  when no other account remains signed in (it is shared by the device).
  Switching registers the token for the newly active account (one row per
  user and device, as before).

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
- **Sender:** the `send-push` Edge Function, below.

### Push sender (2026-11-04)
`supabase/functions/send-push/` (`handler.ts` holds the logic, `index.ts`
serves it). It sends one notification to every active `device_tokens` row of
one user through the FCM HTTP v1 API.
- **Server only.** The caller must send `Authorization: Bearer <service role
  key>` (compared in constant time with `SUPABASE_SERVICE_ROLE_KEY`, which
  Supabase injects); anything else is 401. The anon key or a user's JWT can
  never push, so no user can notify another. Gateway JWT verification stays
  on (default `verify_jwt`).
- **Request:** `POST` JSON
  `{user_id, type, reference_id?, title, body?}`. `user_id` and
  `reference_id` must be uuids, `type` 1-40 of `a-z_` (the app's types, see
  Deep links; an unknown one opens the notification center), `title` 1-100
  characters, `body` at most 500. Invalid input is 400.
- **Message:** `notification {title, body}`,
  `data {type, user_id, reference_id}` (all strings),
  `android.priority = high`, `android.notification.channel_id = alerts_sv`,
  `apns.payload.aps.sound = default`. The caller supplies the text and must
  follow "What a notification may contain": generic text, never amounts or
  contact names.
- **Credentials:** the Firebase service account key (JSON) in the
  `FCM_SERVICE_ACCOUNT` function secret. The function signs an RS256 JWT
  with it (WebCrypto, no dependency) for a Google access token (scope
  `firebase.messaging`) and reuses it for an hour in a warm instance.
- **Tokens:** read and updated through PostgREST with the service role key
  (RLS does not apply to it; it never leaves the server). A send answered
  with FCM `UNREGISTERED` or `SENDER_ID_MISMATCH` sets that row's
  `active = false`. Other failures leave the token alone.
- **Response:** `{sent, failed, deactivated}`; 200, or 502 when nothing was
  sent and something failed (a retry may help; a partial success is 200 so a
  retry does not notify devices twice). No active device is
  `{sent: 0, ...}`. Tokens, texts and keys are never logged; only status and
  FCM error codes are.
- **Not stored:** the push is not written to `notifications`; a caller that
  wants it in the notification center inserts that row itself. Nothing calls
  the function yet: it is the sender a server-side job (cron, database
  webhook, another function) uses.
- **Tests:** `node --test supabase/functions/send-push/handler.test.ts`
  (Node 22.18+ runs the TypeScript directly; `deno test` runs it as well).

### Firebase setup (one time per environment)
1. Create a Firebase project; add Android app `com.finance.tracker` and an
   iOS app with the bundle id from Xcode.
2. Put `google-services.json` in `android/app/` and `GoogleService-Info.plist`
   in `ios/Runner/` (both are gitignored; the Gradle plugin is applied only
   when the Android file exists).
3. iOS: enable the Push Notifications and Background Modes > Remote
   notifications capabilities in Xcode and upload an APNs key to Firebase.
4. Never place FCM server credentials or the Supabase service-role key in the app.
5. Push sender: in Firebase console > Project settings > Service accounts,
   generate a private key (JSON; gitignored as `*firebase-adminsdk*.json`,
   never commit it), then
   `supabase secrets set FCM_SERVICE_ACCOUNT="$(cat <key file>.json)"` and
   `supabase functions deploy send-push`. Call it with
   `curl -X POST https://<project>.supabase.co/functions/v1/send-push
   -H "Authorization: Bearer <service role key>"
   -H "Content-Type: application/json"
   -d '{"user_id":"<uuid>","type":"reminder","reference_id":"<uuid>","title":"Collect payment","body":"Money to collect"}'`.

### Khata due dates (2026-11-04)
A khata entry with a due date gets an ordinary one-time reminder at 09:00
local on that date, so it is scheduled, listed, synced and actionable like any
other reminder. Rules live in `domain/services/khata_due_reminders.dart`
(`KhataDueReminders`). No schema change.
- Id: `uuid v5("contact-transaction-due:<entry id>")`
  (`KhataDueReminders.id`), the same on every device and retry.
- Type/title: credit -> `receivable` "Collect payment", debit -> `payable`
  "Pay dues", others -> `khata` "Khata follow-up" (no name or amount in the
  title). `contact_id` and `amount` are the entry's; `transaction_id` stays
  null (it references `transactions`, not `contact_transactions`).
- **On save** (`ContactFormController._syncDueReminder`): written when the
  entry is new or its due date, type or amount changes (active again, snooze
  cleared); a note-only edit keeps a reminder already marked done. Clearing
  the due date, deleting the entry or deleting the contact soft-deletes it.
  Saving an entry with a due date asks for notification permission the same
  way saving a reminder does.
- **On every reminders load** (`ReminderController._applyKhataDue`, before
  the device schedule is synced; the shell loads at launch, on resume and
  after every data change), `KhataDueReminders.plan`:
  - *Backfill:* an entry due today or later with no live reminder gets one,
    created only if absent (`ReminderRepository.create(onlyIfAbsent: true)`:
    local check including tombstones, server `ignoreDuplicates`), so a
    reminder the user deleted is never brought back. Created done if the dues
    are already cleared. Past due dates are skipped. Backfill waits until this
    device has pulled the account once (`ReminderRepository.hasPulled`, the
    `cursor_pulled` metadata row written after `downloadDelta` in
    `SyncEngine.syncAll`): before that, a reminder another device deleted or
    completed is not in the local database, and a pending local copy would
    win over the server's.
  - *Auto-complete:* an open due reminder is marked done
    (`ReminderCalculator.complete`) when the contact's balance
    (`Contact.getCurrentBalance`) went from having those dues at the previous
    load to not having them now (receivable: they owe nothing, `<= 0`;
    payable: the user owes nothing, `>= 0`; khata: settled). The previous
    load's balance sign per contact is stored as JSON in the account's
    `sync_metadata` (`khata_due_balances`, dropped by `clearAllUserData`), so
    changes made between launches or pulled from another device are compared
    too. Any balance change counts (repayment, deleting any entry, opening
    balance edit, split settlement, sync, restore); a name or photo edit does
    not. A part payment leaves the reminder open, and a reminder the user
    reopens while the dues are cleared stays open until they are owed and
    cleared again. A contact seen for the first time is only recorded.
  - Runs one at a time (`_loadApplyingKhataDue`), each run reading fresh
    data, so overlapping loads cannot save older balances over newer ones.
    Its writes do not call `DataChangeNotifier.markChanged` (that would start
    another load).

### Loan reminders (2026-11-11)
A loan reminder is an ordinary reminder (`ReminderType.loan`, `Reminder.loanId`
set), so it is scheduled, listed, synced and actionable like any other. Rules
live in `LoanRepository`; no further schema change.
- One per open loan. Id: `uuid v5("loan-reminder:<loan id>")`
  (`LoanIds.reminder`), the same on every device and retry. Title
  "Loan payment due" (loan taken) or "Collect loan payment" (loan given), no
  name or amount.
- At 09:00 local on the loan's next due date. Each payment moves it to the next
  due date; closing the loan or deleting it soft-deletes it.
- Payload `loan:<loan id>` (`ReminderNotificationPlanner.payloadFor`, constant
  `loanPayloadType`), tagged `<user id>|` like the others. A tap opens the
  loan's payment form (`NotificationTarget.resolve('loan', id)` ->
  `AppRoutes.loanPaymentForm`, a bad id -> notification center). Notifications
  scheduled earlier keep their `reminder:<id>` payload and open the reminder
  detail as before.
- **Mark done** and **Snooze** work on it: `NotificationTarget.reminderId` maps
  the `loan:` target back to `LoanIds.reminder(<loan id>)` for
  `reminderActionInBackground`.
- The reminder detail of a loan reminder has **Record payment** (opens the
  payment form) and no Edit (the loan owns the date and title); Delete, Mark as
  done and Snooze stay.

### Not in this phase
Notification buttons on iOS, anything that calls the push sender, a
notification-center delete,
and synced notification settings.
