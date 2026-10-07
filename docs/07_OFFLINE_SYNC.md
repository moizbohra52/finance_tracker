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
- sync metadata

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
