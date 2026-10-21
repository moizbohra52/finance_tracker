# Receipt / bill photo on a transaction — design

Date: 2026-10-21. Status: approved in chat, awaiting spec review.

## Goal
Let the user attach one photo of a receipt or bill to an income or expense
transaction, see it later, change or remove it. It must work offline: a photo
taken without network is kept on the phone and uploaded by the next sync.

Success: attach a photo offline, go online, and the photo is on the server and
visible on another device signed in to the same account; nobody else can read it.

## Decisions
- One photo per transaction (the existing single `transactions.attachment_url`).
- Source: camera or gallery. Picked at `maxWidth: 1600`, `imageQuality: 70`
  (about 300 KB), so it fits the 2 MiB limit.
- Accepted types and size: the avatar rules (`AvatarRules`: jpg/jpeg/png/webp,
  at most 2 MiB, not empty). Reused as-is; the bucket enforces the same limits.
- Private storage, owner-only, shown through one-hour signed links (same as
  avatars). Never a public URL.
- Out of scope: several photos per transaction, receipts in CSV/Excel/PDF
  export, receipts on transfers or khata-linked entries, OCR.

## Storage and schema
New migration `supabase/migrations/20261021100000_receipts_bucket.sql`:
- Bucket `receipts`: `public = false`, `file_size_limit = 2097152`,
  `allowed_mime_types = image/jpeg, image/png, image/webp`.
- Four policies on `storage.objects` (select, insert, update, delete),
  `to authenticated`, each requiring `bucket_id = 'receipts'` and
  `(storage.foldername(name))[1] = (select auth.uid())::text`. Copy of the
  avatars policies.

Object name: `<user id>/<transaction id>` (no extension; the content type is set
on upload). One fixed name per transaction makes every upload an idempotent
overwrite (`upsert: true`), so a retried or repeated upload never leaves a
second file.

`transactions.attachment_url` already exists on the server
(`20261006120100_finance_core.sql`) and in local SQLite. It holds the object
name above, not a URL. No table migration and no local DB version change.

## Data layer
`Transaction` entity and `TransactionModel` gain `attachmentUrl` (`attachment_url`),
in fromJson/toJson/copyWith, so it is written locally and sent in sync payloads.
`TransactionController.saveTransaction` carries it over from `existing` on edit.

New `ReceiptStore` (`lib/data/repositories/receipt_store.dart`):
- Local folder `<app documents>/receipts/<user id>/`:
  - `pending/<tx id>.<ext>`: photo waiting for upload. The folder is the queue.
  - `pending/<tx id>.remove`: receipt removed while its server file may still
    exist.
  - `<tx id>.<ext>`: uploaded photo kept on the phone, so the user's own
    receipts show offline.
- `stage(txId, bytes, extension)`: validates with `AvatarRules`, writes the
  pending file (replacing any earlier pending file or `.remove` marker for that
  transaction). Throws a `StorageFailure` with the rule's message when invalid.
- `markRemoved(txId)`: deletes the local files of that transaction and writes
  the `.remove` marker.
- `localFile(txId)`: the pending or cached file, or null.
- `signedLink(path)`: one-hour signed link for a stored object.
- `uploadPending()`: for each pending photo, upload to `<uid>/<txId>`
  (`upsert: true`), move it to the cache, and, when the transaction's
  `attachment_url` differs, update the transaction through
  `TransactionRepository.updateTransaction` (which queues the row upload). For
  each `.remove` marker, delete the object (missing object is fine) and drop
  the marker. A failed item stays pending and the next item is tried; a network
  failure stops the run (the next sync retries).
- `deleteAll(userId)`: best effort, lists `receipts/<uid>` and removes every
  object, then deletes the local folder. For account deletion.
- `deleteLocal(userId)`: deletes the local folder. For sign-out / account
  removal from the device.

Who calls what:
- `SyncEngine.syncAll` runs `uploadPending()` (injected as an optional
  callback) right before `uploadPending()` of the row queue, so the object
  exists before the row that names it is uploaded.
- Saving the form: the transaction is saved first, then `stage()` (if a new
  photo was picked) or `markRemoved()` (if the user removed it, and the row's
  `attachment_url` is cleared in the same save), then `syncAll()` is started.
- Deleting a transaction (`TransactionController.deleteTransaction`) calls
  `markRemoved()` when it had a receipt.
- Account deletion: `deleteAll(uid)` joins the existing `beforeDelete` cleanup
  (next to the avatar removal).
- Sign-out / removing an account from the device: `deleteLocal(uid)` next to
  `AppDatabase.removeUser(uid)`.

## UI
Transaction form (income/expense only), below Note:
- No photo: an outlined "Add receipt photo" button opening a sheet with
  "Take photo" and "Choose from gallery".
- With a photo: thumbnail, "Change" and "Remove". The choice is kept in the
  form state and applied on Save, so Cancel/back discards it.
- Picking runs inside `ExternalActivity.run` (app lock is not triggered on
  return), like the avatar picker. An invalid photo shows the rule message
  inline under the row.

Transaction detail:
- A "Receipt" row with a thumbnail when `attachment_url` is set or a local file
  exists. Tap opens a full-screen viewer (`InteractiveViewer`) with zoom.
- Source order: local file, then signed link. No local file and offline:
  "Receipt will show when you are online". Link or image failure: a short
  error with Retry.
- A pending photo shows a small "Waiting to upload" label.

## Platform
- iOS `Info.plist`: `NSCameraUsageDescription` and
  `NSPhotoLibraryUsageDescription`.
- Android: no manifest change (image_picker uses system intents; the app does
  not declare CAMERA, so no runtime permission is needed).

## Error handling
- Validation failures: `AvatarProblem.message` shown in the form.
- Upload errors are mapped by `guardSupabase`; the photo stays pending and the
  sync status shows the error like other sync failures. No photo is lost
  because the pending file is only deleted after a successful upload.
- Removal and account cleanup are best effort and never block the user action.

## Testing
- `ReceiptStore` with a fake storage client and a temp directory:
  stage then upload sets `attachment_url` and moves the file to the cache; a
  second run uploads nothing; a failed upload keeps the file pending; a
  `.remove` marker deletes the object and the marker; an invalid photo is
  rejected with the rule message.
- `TransactionModel` / entity: `attachment_url` round trip.
- `TransactionController.saveTransaction`: editing keeps `attachmentUrl`.
- SyncEngine: receipts are uploaded before the row queue.
- Form flow test: attaching (with a faked picker) and saving stages the photo.

## Docs
- `docs/03_DATABASE_SCHEMA.md`: migration 10 and the meaning of
  `attachment_url`.
- `docs/04_SECURITY_RLS.md`: receipts bucket and policies, cleanup on account
  deletion.
- `docs/07_OFFLINE_SYNC.md`: the pending folder as the receipt upload queue.

## Deployment
Apply `20261021100000_receipts_bucket.sql` before shipping. Without the bucket,
uploads fail and photos stay pending on the phone (nothing is lost).
