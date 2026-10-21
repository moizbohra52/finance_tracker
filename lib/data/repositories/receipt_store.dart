import 'dart:io';
import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/avatar_rules.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Receipt photos of transactions (docs/superpowers/specs/
/// 2026-10-21-receipt-photo-design.md).
///
/// A photo is first kept on the phone in the user's `pending` folder (under
/// `receipts/<user id>/` in the app documents), which is the upload queue,
/// so attaching works offline. SyncEngine uploads the queue before the row
/// queue. On the server a photo is `<user id>/<transaction id>` in the
/// private [bucket]; after upload the phone keeps a copy to show offline.
class ReceiptStore {
  ReceiptStore(
    this._client,
    this._transactions, {
    Future<Directory> Function()? documents,
  }) : _documents = documents ?? getApplicationDocumentsDirectory;

  static const String bucket = 'receipts';
  static const Duration linkLifetime = Duration(hours: 1);

  /// Extension of the marker for a receipt removed before its server file.
  static const String _removed = 'remove';

  final SupabaseClient? _client;
  final TransactionRepository _transactions;
  final Future<Directory> Function() _documents;

  static String objectPath(String userId, String txId) => '$userId/$txId';

  String? get currentUserId => _client?.auth.currentUser?.id;

  /// Called when a photo or removal is queued, to start a sync (main.dart).
  void Function()? onQueued;

  /// Keeps [bytes] as the receipt of [txId] until the next sync uploads it,
  /// replacing any earlier photo or removal of that transaction.
  Future<void> stage(String txId, Uint8List bytes, String fileName) async {
    final AvatarProblem? problem = AvatarRules.check(
      fileName: fileName,
      byteLength: bytes.length,
    );
    if (problem != null) throw StorageFailure(problem.message);
    final String? uid = currentUserId;
    if (uid == null) throw AuthFailure.sessionExpired;
    await _clear(uid, txId);
    final Directory pending = await (await _pending(
      uid,
    )).create(recursive: true);
    final String name = '$txId.${AvatarRules.extensionOf(fileName)}';
    // Written beside the queue and moved in whole, so a running upload never
    // reads a half-written photo.
    final File part = await File(
      p.join((await _folder(uid)).path, '$name.part'),
    ).writeAsBytes(bytes, flush: true);
    await part.rename(p.join(pending.path, name));
    onQueued?.call();
  }

  /// Drops the photo of [txId] from the phone and queues the removal of its
  /// server file.
  Future<void> markRemoved(String txId) async {
    final String? uid = currentUserId;
    if (uid == null) return;
    await _clear(uid, txId);
    final Directory pending = await (await _pending(
      uid,
    )).create(recursive: true);
    await File(p.join(pending.path, '$txId.$_removed')).writeAsBytes(<int>[]);
    onQueued?.call();
  }

  /// Photos of the signed-in user not uploaded yet. Signing out would lose
  /// them, so they count as unsynced changes.
  Future<int> pendingPhotoCount() async {
    final String? uid = currentUserId;
    if (uid == null) return 0;
    final Directory pending = await _pending(uid);
    if (!await pending.exists()) return 0;
    return pending
        .list()
        .where((FileSystemEntity e) => e is File && !_isMarker(e))
        .length;
  }

  /// The photo of [txId] on this phone, waiting or uploaded, or null.
  Future<File?> localFile(String txId) async {
    final String? uid = currentUserId;
    if (uid == null) return null;
    for (final Directory dir in <Directory>[
      await _pending(uid),
      await _folder(uid),
    ]) {
      for (final File file in await _filesOf(dir, txId)) {
        if (!_isMarker(file)) return file;
      }
    }
    return null;
  }

  /// The bytes of [localFile], read fresh, so a changed photo never shows
  /// from the image cache.
  Future<Uint8List?> localBytes(String txId) async =>
      (await localFile(txId))?.readAsBytes();

  Future<bool> isPending(String txId) async {
    final String? uid = currentUserId;
    if (uid == null) return false;
    return (await _filesOf(
      await _pending(uid),
      txId,
    )).any((File f) => !_isMarker(f));
  }

  /// Sends the signed-in user's queue: uploads waiting photos and links them
  /// to their transactions, and deletes the server files of removed ones. A
  /// failed item stays queued for the next sync; being offline stops the run.
  Future<void> uploadPending() async {
    final String? uid = currentUserId;
    if (uid == null) return;
    final Directory pending = await _pending(uid);
    if (!await pending.exists()) return;
    final Directory folder = await _folder(uid);
    final List<FileSystemEntity> entries = await pending.list().toList();
    for (final FileSystemEntity entry in entries) {
      if (entry is! File) continue;
      final String txId = p.basenameWithoutExtension(entry.path);
      final String extension = p.extension(entry.path).replaceFirst('.', '');
      final String path = objectPath(uid, txId);
      try {
        if (extension == _removed) {
          await removeObjects(<String>[path]);
          await entry.delete();
          continue;
        }
        final String? contentType = AvatarRules.contentTypes[extension];
        if (contentType == null) {
          await entry.delete(); // Not written by stage(); nothing to send.
          continue;
        }
        final FileStat before = await entry.stat();
        await putObject(path, await entry.readAsBytes(), contentType);
        // Replaced (or removed) during the upload: the next sync sends that.
        if (!_unchanged(before, await entry.stat())) continue;
        await _link(txId, path);
        // Moved only once linked, so a failed link is retried next sync.
        await entry.rename(p.join(folder.path, p.basename(entry.path)));
      } on NetworkFailure {
        rethrow;
      } on AppException {
        // This one waits for the next sync; the others still go.
      } on FileSystemException {
        // Same: a photo that cannot be read must not hold back the rows.
      }
    }
  }

  /// A one-hour link to a stored receipt; never a public URL.
  Future<String> signedLink(String objectPath) => guardSupabase(
    () => _storage.createSignedUrl(objectPath, linkLifetime.inSeconds),
  );

  /// Every receipt of the signed-in user, on the server and on this phone.
  /// Best effort, for account deletion: a failure must not block it.
  Future<void> deleteAll() async {
    final String? uid = currentUserId;
    if (uid == null) return;
    try {
      final List<String> paths = await listObjects(uid);
      if (paths.isNotEmpty) await removeObjects(paths);
    } on Object {
      // Left behind, like an avatar that could not be removed (docs/04).
    }
    try {
      await deleteLocal(uid);
    } on Object {
      // The app's own folder; nothing else can be done about it here.
    }
  }

  /// The photos of [userId] kept on this phone (sign-out, account removal).
  Future<void> deleteLocal(String userId) async {
    final Directory folder = await _folder(userId);
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  Future<void> putObject(String path, Uint8List bytes, String contentType) =>
      guardSupabase(
        () => _storage.uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        ),
      );

  Future<void> removeObjects(List<String> paths) =>
      guardSupabase(() => _storage.remove(paths));

  /// Full object names under [folder].
  Future<List<String>> listObjects(String folder) => guardSupabase(() async {
    const int pageSize = 100;
    final List<String> names = <String>[];
    while (true) {
      final List<FileObject> page = await _storage.list(
        path: folder,
        searchOptions: SearchOptions(limit: pageSize, offset: names.length),
      );
      names.addAll(page.map((FileObject f) => '$folder/${f.name}'));
      if (page.length < pageSize) return names;
    }
  });

  StorageFileApi get _storage {
    final SupabaseClient? client = _client;
    if (client == null) throw AuthFailure.sessionExpired;
    return client.storage.from(bucket);
  }

  Future<void> _link(String txId, String path) async {
    final Transaction tx = await _transactions.getTransactionById(txId);
    if (tx.attachmentUrl == path) return;
    await _transactions.updateTransaction(
      tx.copyWith(attachmentUrl: path, updatedAt: DateTime.now()),
    );
  }

  Future<Directory> _folder(String userId) async =>
      Directory(p.join((await _documents()).path, 'receipts', userId));

  Future<Directory> _pending(String userId) async =>
      Directory(p.join((await _folder(userId)).path, 'pending'));

  bool _isMarker(File file) => p.extension(file.path) == '.$_removed';

  static bool _unchanged(FileStat before, FileStat after) =>
      after.type == FileSystemEntityType.file &&
      after.size == before.size &&
      after.modified == before.modified;

  /// Every file of [txId] in [dir], whatever its extension.
  Future<List<File>> _filesOf(Directory dir, String txId) async {
    if (!await dir.exists()) return <File>[];
    return <File>[
      await for (final FileSystemEntity e in dir.list())
        if (e is File && p.basenameWithoutExtension(e.path) == txId) e,
    ];
  }

  Future<void> _clear(String userId, String txId) async {
    for (final Directory dir in <Directory>[
      await _pending(userId),
      await _folder(userId),
    ]) {
      for (final File file in await _filesOf(dir, txId)) {
        await file.delete();
      }
    }
  }
}
