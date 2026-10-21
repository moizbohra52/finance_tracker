# Receipt Photo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One receipt photo per income/expense transaction, attachable offline, uploaded to a private Supabase bucket by the next sync.

**Architecture:** `transactions.attachment_url` (already on server and in SQLite) holds the storage object name `<uid>/<txId>`. A new `ReceiptStore` keeps photos in `<documents>/receipts/<uid>/` — `pending/` is the upload queue — and `SyncEngine.syncAll` uploads them right before the row queue. The form stages/removes a photo on Save; the detail view shows it from the local file or a one-hour signed link.

**Tech Stack:** Flutter, GetX, supabase_flutter storage, sqflite, image_picker (installed), path_provider (installed).

**Spec:** `docs/superpowers/specs/2026-10-21-receipt-photo-design.md`

## Global Constraints
- Bucket `receipts`: private, `file_size_limit = 2097152`, mime `image/jpeg`, `image/png`, `image/webp`; four owner-only policies copied from the `avatars` ones in `supabase/migrations/20261008120000_profile_settings.sql`.
- Object name `<user id>/<transaction id>`, no extension, uploaded with `upsert: true` and the content type from `AvatarRules.contentTypes`.
- Validation is `AvatarRules.check(fileName:, byteLength:)` unchanged; its `AvatarProblem.message` is the user-facing text.
- Picker options: `maxWidth: 1600`, `imageQuality: 70`; picking runs inside `ExternalActivity.run`.
- Signed links last `Duration(hours: 1)`; never a public URL.
- No new packages. No `transactions` table migration, no local DB version change.
- Receipts only on income/expense (the form's types). Not in export.
- Do not commit; the user commits. Each task ends with `flutter analyze` clean and its tests green.
- The user applies Supabase SQL by hand: write the migration, do not run it.

## Review Focus
1. Editing a transaction (amount, note) without touching the receipt must keep `attachment_url` — Task 1 test `editing keeps the receipt`.
2. A photo attached offline to a transaction that is then deleted before any sync must never be uploaded — Task 2 test `a removed receipt is not uploaded`.
3. Account B signing in on the same phone must not upload or show account A's pending photos — Task 2 test `only the signed-in user's photos are uploaded`.
4. Changing the photo twice offline (jpg then png) uploads only the last one, once — Task 2 test `staging again replaces the earlier photo`.
5. Opening a receipt synced from another device while offline shows a message, not a crash or endless spinner — Task 5 test `offline without a local copy says it will show online`.

---

### Task 1: `attachmentUrl` on the transaction

**Files:**
- Modify: `lib/domain/entities/transaction.dart` (field, constructor, fromJson, toJson, copyWith)
- Modify: `lib/data/models/transaction.dart` (field, fromJson, toJson, toEntity, fromEntity)
- Modify: `lib/features/transactions/controller/transaction_controller.dart:251-286` (`saveTransaction`)
- Test: `test/unit/receipts/transaction_attachment_test.dart`

**Interfaces:**
- Produces: `Transaction.attachmentUrl` (`String?`, json key `attachment_url`); `copyWith({String? attachmentUrl})` sets but cannot clear (same as the other nullable fields).

- [ ] **Step 1: Write the failing tests**

```dart
test('attachment_url survives the model round trip', () {
  // Build a TransactionModel from a json map that has 'attachment_url': 'u/tx-1'
  // → toEntity().attachmentUrl == 'u/tx-1'
  // → TransactionModel.fromEntity(entity).toJson()['attachment_url'] == 'u/tx-1'
  // and Transaction.fromJson(entity.toJson()).attachmentUrl == 'u/tx-1'
});

test('editing keeps the receipt', () async {
  // FakeFinance with account 'acc-1' and a stored expense 'tx-1' whose
  // attachmentUrl is 'user-1/tx-1'; TransactionController over its repositories.
  // saveTransaction(id: 'tx-1', existing: stored, amount: 99, note: 'changed', ...)
  expect(finance.transactions.single.attachmentUrl, 'user-1/tx-1');
});
```

- [ ] **Step 2: Run** `flutter test test/unit/receipts/transaction_attachment_test.dart` — expect compile failure (`attachmentUrl` not defined).
- [ ] **Step 3: Implement** the field in entity and model; in `saveTransaction` pass `attachmentUrl: existing?.attachmentUrl` to the `Transaction(...)` it builds. (`FakeFinance.addTransaction` gains an optional `String? attachmentUrl`.)
- [ ] **Step 4: Run** the test file and `flutter test test/features/finance` — PASS.

### Task 2: `ReceiptStore`, bucket migration, docs

**Files:**
- Create: `lib/data/repositories/receipt_store.dart`
- Create: `supabase/migrations/20261021100000_receipts_bucket.sql`
- Modify: `docs/03_DATABASE_SCHEMA.md` (migration 10; `attachment_url` holds the object name), `docs/04_SECURITY_RLS.md` (receipts bucket, cleanup), `docs/07_OFFLINE_SYNC.md` (pending folder is the receipt queue)
- Create: `test/helpers/fake_receipts.dart` — `FakeReceiptStore extends ReceiptStore`, reused by Tasks 3–5
- Test: `test/unit/receipts/receipt_store_test.dart`

**Interfaces:**
- Test helper `FakeReceiptStore(TransactionRepository, Directory root)`: settable `String? currentUserId` (default `'user-1'`), `bool failNextPut` (next `putObject` throws `NetworkFailure`), `List<String> listed` (returned by `listObjects`), `Object? linkError` (thrown by `signedLink`); records `List<String> puts`, `List<String> contentTypes`, `List<String> removed`, `List<String> markedRemoved` (calls to `markRemoved`, then delegates to super), `int deleteAllCalls`, `int signedLinkCalls`.
- Consumes: `Transaction.attachmentUrl`, `TransactionRepository.getTransactionById(String)`, `TransactionRepository.updateTransaction(Transaction)`, `AvatarRules`.
- Produces (class `ReceiptStore`):
  - `ReceiptStore(SupabaseClient? client, TransactionRepository transactions, {Future<Directory> Function()? documents})` — `documents` defaults to `getApplicationDocumentsDirectory`.
  - `static const String bucket = 'receipts';` `static String objectPath(String userId, String txId) => '$userId/$txId';`
  - `String? get currentUserId` (session user; tests override)
  - `Future<void> stage(String txId, Uint8List bytes, String fileName)` — throws `StorageFailure(problem.message)` when `AvatarRules.check` fails
  - `Future<void> markRemoved(String txId)`
  - `Future<File?> localFile(String txId)` — pending first, then cached
  - `Future<bool> isPending(String txId)`
  - `Future<void> uploadPending()`
  - `Future<String> signedLink(String objectPath)`
  - `Future<void> deleteAll()` — current user, best effort, never throws
  - `Future<void> deleteLocal(String userId)`
  - Storage calls, each a public method so tests subclass and override (as `FileSharingService` fakes do): `Future<void> putObject(String path, Uint8List bytes, String contentType)`, `Future<void> removeObjects(List<String> paths)`, `Future<List<String>> listObjects(String folder)` — all through `guardSupabase`.

- [ ] **Step 1: Write the failing tests** (`FakeReceiptStore` over a temp dir from `Directory.systemTemp.createTemp()`; FakeFinance holds `tx-1` without a receipt)

```dart
test('a staged photo uploads once and is linked to its transaction', () async {
  await store.stage('tx-1', bytes(10), 'IMG_1.jpg');
  expect(await store.isPending('tx-1'), isTrue);
  await store.uploadPending();
  expect(store.puts, <String>['user-1/tx-1']);
  expect(store.contentTypes.single, 'image/jpeg');
  expect(finance.transactions.single.attachmentUrl, 'user-1/tx-1');
  expect(await store.isPending('tx-1'), isFalse);
  expect(await store.localFile('tx-1'), isNotNull, reason: 'kept as cache');
  await store.uploadPending();
  expect(store.puts, hasLength(1), reason: 'nothing left to send');
});

test('a failed upload keeps the photo pending', () async {
  await store.stage('tx-1', bytes(10), 'a.jpg');
  store.failNextPut = true;
  await expectLater(store.uploadPending(), throwsA(isA<NetworkFailure>()));
  expect(await store.isPending('tx-1'), isTrue);
  expect(finance.transactions.single.attachmentUrl, isNull);
});

test('an invalid photo is refused with the rule message', () async {
  await expectLater(
    store.stage('tx-1', bytes(10), 'scan.pdf'),
    throwsA(isA<StorageFailure>().having((e) => e.message, 'message',
        AvatarProblem.unsupportedType.message)),
  );
});

test('a removed receipt is not uploaded and its file is deleted', () async {
  await store.stage('tx-1', bytes(10), 'a.jpg');
  await store.markRemoved('tx-1');
  expect(await store.localFile('tx-1'), isNull);
  await store.uploadPending();
  expect(store.puts, isEmpty);
  expect(store.removed, <String>['user-1/tx-1']);
  await store.uploadPending();
  expect(store.removed, hasLength(1), reason: 'marker dropped');
});

test('staging again replaces the earlier photo', () async {
  await store.stage('tx-1', bytes(10), 'a.jpg');
  await store.stage('tx-1', bytes(20), 'b.png');
  await store.uploadPending();
  expect(store.puts, <String>['user-1/tx-1']);
  expect(store.contentTypes.single, 'image/png');
});

test('only the signed-in user\'s photos are uploaded', () async {
  await store.stage('tx-1', bytes(10), 'a.jpg');
  store.currentUserId = 'user-2';
  await store.uploadPending();
  expect(store.puts, isEmpty);
  expect(await store.localFile('tx-1'), isNull);
});

test('deleteAll removes every stored receipt and the local folder', () async {
  store.listed = <String>['user-1/tx-1', 'user-1/tx-2'];
  await store.stage('tx-1', bytes(10), 'a.jpg');
  await store.deleteAll();
  expect(store.removed, <String>['user-1/tx-1', 'user-1/tx-2']);
  expect(await store.localFile('tx-1'), isNull);
});
```

- [ ] **Step 2: Run** `flutter test test/unit/receipts/receipt_store_test.dart` — FAIL (no `ReceiptStore`).
- [ ] **Step 3: Implement `ReceiptStore`.** Folder `<documents>/receipts/<uid>/`, `pending/` inside it. `stage` deletes any `pending/<txId>.*` (photo or `.remove`) and cached `<txId>.*` before writing `pending/<txId>.<ext>`. `markRemoved` deletes `pending/<txId>.*` and `<txId>.*`, then writes `pending/<txId>.remove`. `uploadPending` with no user returns; otherwise per entry of `pending/`:
  - `.remove` → `removeObjects([objectPath])`, delete marker.
  - photo → `putObject`, rename to `<txId>.<ext>` in the user folder, then `getTransactionById` and, if `attachmentUrl != objectPath`, `updateTransaction(tx.copyWith(attachmentUrl: objectPath, updatedAt: DateTime.now()))`.
  - `NetworkFailure` rethrows (stops the run); any other `AppException` skips that entry.
  `deleteAll` catches every `Object` (best effort). `listObjects` pages through `storage.from(bucket).list(path: folder)`.
- [ ] **Step 4: Write the migration** exactly as the Global Constraints bucket line (insert into `storage.buckets` with `on conflict (id) do update`, then the four policies named "Users can read/upload/update/delete their own receipts").
- [ ] **Step 5: Update the three docs** (migration 10 entry with "apply before shipping; without it photos stay pending"; receipts bucket under Storage in 04 incl. account-deletion cleanup by `ReceiptStore.deleteAll`; pending folder in 07).
- [ ] **Step 6: Run** the test file — PASS; `flutter analyze` — clean.

### Task 3: Wire the store into sync, account deletion and sign-out

**Files:**
- Modify: `lib/core/services/sync_engine.dart` (field `Future<void> Function()? uploadFiles;`, called in `syncAll` after `claimLocalData` and before `uploadPending()`)
- Modify: `lib/main.dart` (build `ReceiptStore(client, repositories.transactions)` after `repositories`; `syncEngine.uploadFiles = receipts.uploadPending;` pass `receiptStore: receipts` to `FinanceTrackerApp`)
- Modify: `lib/main.dart` `FinanceTrackerApp` + `lib/bindings/initial_binding.dart` (optional `ReceiptStore? receiptStore`; `Get.put<ReceiptStore>(…, permanent: true)` when non-null; pass to `AccountSwitchController`)
- Modify: `lib/features/auth/controllers/account_switch_controller.dart` (optional `ReceiptStore? receipts`; `_removeLocalData` also awaits `receipts?.deleteLocal(userId)`)
- Modify: `lib/features/profile/controllers/profile_controller.dart` (optional named `ReceiptStore? receipts`; `_removeAvatarBeforeDelete` also awaits `receipts?.deleteAll()`); `lib/bindings/feature_bindings.dart:237` passes `Get.isRegistered<ReceiptStore>() ? Get.find<ReceiptStore>() : null`
- Test: `test/features/profile/profile_test.dart` (one new test)

**Interfaces:**
- Consumes: `ReceiptStore.uploadPending()`, `deleteAll()`, `deleteLocal(String)`.
- Produces: `Get.find<ReceiptStore>()` available app-wide when the app runs with Supabase.

- [ ] **Step 1: Write the failing test** in `profile_test.dart`: deleting the account with a `FakeReceiptStore` passed to `ProfileController` → `expect(receipts.deleteAllCalls, 1)`.
- [ ] **Step 2: Run** it — FAIL.
- [ ] **Step 3: Implement** the wiring above. The `syncAll` ordering has no test harness (it needs a live Supabase session); keep it to the single line before `await uploadPending();` with comment `// Objects first, so an uploaded row never names a missing file.`
- [ ] **Step 4: Run** `flutter test test/features/profile test/features/auth test/core/services` and `flutter analyze` — the new test passes; failures, if any, are the pre-existing ones (compare with `git stash` baseline).

### Task 4: Attach, change and remove in the form; delete cleanup

**Files:**
- Modify: `lib/features/transactions/controller/transaction_controller.dart` (optional named `ReceiptStore? receipts` in the constructor; `saveTransaction` gains `({Uint8List bytes, String fileName})? newReceipt` and `bool removeReceipt = false`; `deleteTransaction` calls `markRemoved` when the deleted transaction had a receipt or a pending photo)
- Modify: `lib/bindings/feature_bindings.dart` (`TransactionBinding` passes the store as in Task 3)
- Create: `lib/features/transactions/widgets/receipt_field.dart` (form row: add button → sheet "Take photo"/"Choose from gallery"; thumbnail with Change/Remove; inline `AvatarProblem` message)
- Modify: `lib/features/transactions/views/transaction_form_view.dart` (state `_newReceipt`, `_removeReceipt`; `ReceiptField` between Note and the error/Save block; pass both to `saveTransaction`)
- Modify: `ios/Runner/Info.plist` (`NSCameraUsageDescription`: "Take a photo of a receipt to keep with a transaction.", `NSPhotoLibraryUsageDescription`: "Choose a receipt photo to keep with a transaction.")
- Test: `test/unit/receipts/transaction_receipt_test.dart` (controller tests replace the spec's picker flow test: image_picker cannot be faked without importing its platform interface, a transitive dependency)

**Interfaces:**
- Consumes: Task 2 `stage`, `markRemoved`, `localFile`.
- Produces: `ReceiptField({required String? existingPath, required String transactionId, required ValueChanged<({Uint8List bytes, String fileName})?> onPicked, required VoidCallback onRemoved})`.

- [ ] **Step 1: Write the failing tests** (FakeFinance + `FakeReceiptStore`):

```dart
test('saving with a new photo stages it for the transaction', ...);
  // saveTransaction(id: 'tx-9', newReceipt: (bytes: b, fileName: 'r.jpg'), ...)
  // expect(await receipts.isPending('tx-9'), isTrue)
test('removing the receipt clears it and marks the file removed', ...);
  // existing has attachmentUrl 'user-1/tx-1'; saveTransaction(..., removeReceipt: true)
  // expect(finance.transactions.single.attachmentUrl, isNull)
  // expect(receipts.markedRemoved, <String>['tx-1'])
test('deleting a transaction with a receipt removes the receipt', ...);
  // expect(receipts.markedRemoved, <String>['tx-1'])
test('an invalid photo fails the save before anything is written', ...);
  // newReceipt fileName 'x.gif' → save returns false, save.error == AvatarProblem.unsupportedType.message,
  // finance.transactions is unchanged
```

- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.** In `saveTransaction`: check `AvatarRules.check` first and throw `StorageFailure(problem.message)` (so nothing is saved); build the transaction with `attachmentUrl: removeReceipt ? null : existing?.attachmentUrl`; save; then `stage` or (when `removeReceipt`) `markRemoved`. `ReceiptField` picks with `ImagePicker().pickImage(source:, maxWidth: 1600, imageQuality: 70)` inside `ExternalActivity.run`, reads bytes, validates with `AvatarRules.check` and shows the message instead of accepting an invalid photo. Thumbnail: `Image.memory` for a new pick, else `localFile` via `FutureBuilder`, else an icon.
- [ ] **Step 4: Run** the test file, `flutter test test/features/finance`, `flutter analyze` — PASS / clean.

### Task 5: Show the receipt on the transaction detail

**Files:**
- Create: `lib/features/transactions/widgets/receipt_preview.dart` (`ReceiptPreview({required Transaction transaction})`: local file → `Image.file`; else if `attachmentUrl != null` → `signedLink` → `Image.network`; tap opens a full-screen route with `InteractiveViewer`; "Waiting to upload" label when `isPending`)
- Modify: `lib/features/transactions/views/transaction_detail_view.dart` (a "Receipt" row after Note when `attachmentUrl != null` or a local file exists; store found with `Get.isRegistered<ReceiptStore>()`)
- Test: `test/unit/receipts/receipt_preview_test.dart` (widget tests)

**Interfaces:**
- Consumes: Task 2 `localFile`, `isPending`, `signedLink`.

- [ ] **Step 1: Write the failing widget tests** (pump `ReceiptPreview` in a `MaterialApp` with `Get.put<ReceiptStore>(fake)`):

```dart
testWidgets('offline without a local copy says it will show online', ...);
  // transaction.attachmentUrl = 'user-1/tx-1', no local file, signedLink throws NetworkFailure
  // expect(find.text('Receipt will show when you are online'), findsOneWidget)
testWidgets('a pending photo says it is waiting to upload', ...);
  // stage a photo; expect(find.text('Waiting to upload'), findsOneWidget)
testWidgets('another failure offers a retry', ...);
  // signedLink throws DatabaseFailure → find.text('Retry') taps → signedLink called twice
```

- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** `ReceiptPreview` (StatefulWidget holding the load future; `NetworkFailure` → the online message; other `AppException` → short message + Retry) and the detail row.
- [ ] **Step 4: Run** the file, then the whole suite `flutter test` and `flutter analyze`. Expected: analyzer clean; only the 28 failures that also fail on the unmodified code (app_lock, planning, profile, reports, settings_flow, app_test).
