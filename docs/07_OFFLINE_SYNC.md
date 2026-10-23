# Offline-First and Synchronization

## Goal
The user can create/view financial data during temporary network loss.

## Local database
Use Drift/SQLite (or another robust relational local DB) for transactional offline data.

Store:
- accounts
- categories
- transactions
- contacts
- contact transactions
- budgets
- recurring transactions
- reminders
- savings goals (database version 3; older files get the table on upgrade)
- sync metadata

### One database file per signed-in account (2026-10-15)
Several accounts can be signed in on one device (account switching, see
`docs/02_ARCHITECTURE.md`). Each has its own SQLite file,
`<database>_<user id>.db` (`AppDatabase.fileNameFor`); the shared name
(`finance_tracker.db` / `finance_tracker_dev.db`) is the signed-out file.
- Repositories reach SQLite only through `AppDatabase.db`, which is always the
  active account's file, so no repository changed.
- Switching: `AccountSwitchController` removes the account's screens and
  controllers, then inside `SyncEngine.whilePaused` (lets a running sync
  finish, refuses new ones) activates the other session and calls
  `AppDatabase.openFor`. `openFor` closes the old file and waits 300 ms before
  opening the next: repository writes are several statements (row, then queue
  item), so a write already under way fails on the closed file instead of
  landing in the next account's file.
- Unsent changes stay in their own account's file while another account is
  active and upload when that account is active again. A switch works offline.
- Sign-out deletes the signed-out account's file (as sign-out always cleared
  this user's local data); an account whose session ended is removed the same
  way. `SyncEngine.claimLocalData` stays as a safety net.
- Upgrade: the first time an account opens and has no file yet, the shared
  file becomes its file when its `local_owner` is that account (or unset), so
  an update keeps unsent changes instead of downloading again.

## IDs
Generate UUID client-side for locally created records. The client UUID is the
server row's `id` (no separate client_id), so an upload is an upsert on `id`.

## Sync status
Each syncable record may have:
- pending
- synced
- failed
- conflict

Sync status lives only in the local database; server tables have no
sync_status column.

Server `updated_at` is assigned by a trigger on insert and update (client
values are ignored), so it is the pull cursor. It is the server transaction
start time, so re-read a short overlap window before the last cursor.

## Upload
When online:
1. find pending records
2. upload idempotently using client UUID
3. mark synced only after server success

The queue is uploaded in FIFO order, 100 items per read, until it is empty.
An item that keeps failing does not hold back the items after it, except a
`replace` item (see Backup restore), which stops the sync until it succeeds.

Receipt photos are files, not queue rows. A photo attached offline is kept in
`<app documents>/receipts/<user id>/pending/`, which is their queue
(`ReceiptStore`). Each sync uploads that folder first, before the row queue,
so a row never names a file the server does not have yet. An upload is an
overwrite of `<user id>/<transaction id>`, so a retry never adds a second
file. A photo leaves the folder only after it is uploaded and its
transaction's `attachment_url` is set; a removed receipt leaves a `.remove`
marker there until its server file is deleted. Only the signed-in user's
folder is sent.

## Backup restore
A restored backup is uploaded like any other change, so the server ends up
matching the device (`BackupService.restoreBackup`):
- Every restored entry is written as `pending` and queued as a `create`
  (an upsert on `id`), parents before the rows that reference them. Its
  payload carries `__restore`, so the upload also sends the backup's
  `deleted_at`: an entry deleted after the backup was taken comes back, and
  one deleted in the backup is deleted on the server. System categories are
  never uploaded.
- Settings and the profile are single rows the app may only update. A restore
  applies the backup's editable values to the signed-in user's rows and queues
  them as an `update`. NOT NULL columns without a value in the backup keep the
  current value. The avatar is kept: a backup holds only its storage path.
- A clean restore (replace) first deletes every local entry, including ones
  never synced, and their queued changes. It then queues one `replace` item per
  entry table, ahead of the restored rows. On upload it reads the user's live
  server ids page by page and soft-deletes every id the backup does not
  contain, including rows this device never pulled. Entries created after the
  restore are queued behind it, so they are never deleted by it.

## Download
Pull changes after the last successful sync cursor/timestamp.

## Conflict strategy
For financial transactions, never silently merge monetary values.
Prefer immutable transaction records.
For editable metadata, use updated_at/version and explicit conflict handling.

## Duplicate prevention
A retry must not create a duplicate transaction.

## Deletion
Use tombstones/soft-delete for synced records so deletes can propagate.

## Connectivity
Use a connectivity service, but do not assume network availability means internet access.

## UX
Show:
- Offline
- Syncing
- Synced
- Sync failed

Do not block normal local usage because sync failed.

## Security
Local sensitive data should be protected appropriately. Never store raw passwords.
