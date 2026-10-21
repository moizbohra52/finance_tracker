import 'dart:io';
import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/data/repositories/receipt_store.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';

/// ReceiptStore over a temp folder, with the storage calls recorded instead
/// of sent.
class FakeReceiptStore extends ReceiptStore {
  FakeReceiptStore(TransactionRepository transactions, Directory root)
    : super(null, transactions, documents: () async => root);

  @override
  String? currentUserId = 'user-1';

  /// The next upload fails as if offline.
  bool failNextPut = false;

  /// Uploads of this object name fail with a file error (a broken photo).
  String? brokenPath;

  /// Runs during each upload, before it is recorded.
  Future<void> Function()? onPut;

  /// Object names returned by [listObjects].
  List<String> listed = <String>[];

  /// Thrown by [signedLink] when set.
  AppException? linkError;

  final List<String> puts = <String>[];
  final List<String> contentTypes = <String>[];
  final List<int> putSizes = <int>[];
  final List<String> removed = <String>[];
  final List<String> markedRemoved = <String>[];
  int deleteAllCalls = 0;
  int signedLinkCalls = 0;

  @override
  Future<void> putObject(
    String path,
    Uint8List bytes,
    String contentType,
  ) async {
    if (failNextPut) {
      failNextPut = false;
      throw const NetworkFailure();
    }
    if (path == brokenPath) throw const FileSystemException('unreadable');
    await onPut?.call();
    puts.add(path);
    contentTypes.add(contentType);
    putSizes.add(bytes.length);
  }

  @override
  Future<void> removeObjects(List<String> paths) async => removed.addAll(paths);

  @override
  Future<List<String>> listObjects(String folder) async => listed;

  @override
  Future<String> signedLink(String objectPath) async {
    signedLinkCalls++;
    final AppException? error = linkError;
    if (error != null) throw error;
    return 'https://example.test/$objectPath';
  }

  @override
  Future<void> markRemoved(String txId) {
    markedRemoved.add(txId);
    return super.markRemoved(txId);
  }

  @override
  Future<void> deleteAll() {
    deleteAllCalls++;
    return super.deleteAll();
  }
}
