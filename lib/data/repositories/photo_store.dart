import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/domain/services/avatar_rules.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Photos of khata contacts and split groups.
///
/// A photo is `<user id>/<folder>/<id>-<ms>.<ext>` in the private avatars
/// bucket, whose policies already keep each user in their own first folder.
/// The time in the name makes every new photo a new object, so another
/// phone sees the change through the row's avatar_url and never shows a
/// stale copy. Setting a photo needs the network, like the profile photo;
/// once uploaded or downloaded it is kept on the phone and shows offline.
class PhotoStore {
  PhotoStore(this._client, {Future<Directory> Function()? documents})
    : _documents = documents ?? getApplicationDocumentsDirectory;

  static const String bucket = 'avatars';
  static const String contacts = 'contacts';
  static const String groups = 'groups';

  final SupabaseClient? _client;
  final Future<Directory> Function() _documents;

  /// One load per photo at a time, so a list does not fetch it once per row.
  final Map<String, Future<File?>> _loads = <String, Future<File?>>{};

  /// Uploads [bytes] as the photo of [id] in [folder] and returns its object
  /// name, which the caller saves on the row.
  Future<String> upload({
    required String folder,
    required String id,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final AvatarProblem? problem = AvatarRules.check(
      fileName: fileName,
      byteLength: bytes.length,
    );
    if (problem != null) throw StorageFailure(problem.message);
    final String? uid = _client?.auth.currentUser?.id;
    if (uid == null) throw AuthFailure.sessionExpired;
    final String extension = AvatarRules.extensionOf(fileName);
    final String path =
        '$uid/$folder/$id-${DateTime.now().millisecondsSinceEpoch}.$extension';
    await guardSupabase(
      () => _storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: AvatarRules.contentTypes[extension],
          upsert: true,
        ),
      ),
    );
    _loads[path] = Future<File?>.value(await _keep(path, bytes));
    return path;
  }

  /// The photo at [path]: the phone's copy, else downloaded once and kept.
  /// Null when it cannot be fetched now (offline); a later call tries again.
  Future<File?> file(String path) =>
      _loads[path] ??= _load(path).then((File? file) {
        if (file == null) unawaited(_loads.remove(path));
        return file;
      });

  /// Deletes the server object and the phone's copy. Best effort: a photo
  /// left behind must not fail the change that replaced or removed it.
  Future<void> remove(String path) async {
    unawaited(_loads.remove(path));
    try {
      await guardSupabase(() => _storage.remove(<String>[path]));
    } on AppException {
      // Left on the server; it is no longer named by any row.
    }
    try {
      final File local = await _local(path);
      if (await local.exists()) await local.delete();
    } on FileSystemException {
      // The app's own folder; nothing else can be done about it here.
    }
  }

  /// Every contact and group photo of the signed-in user, on the server and
  /// on this phone. Best effort, for account deletion: a failure must not
  /// block it (storage is not cleared by the database cascade, docs/04).
  Future<void> deleteAll() async {
    final String? uid = _client?.auth.currentUser?.id;
    if (uid == null) return;
    for (final String folder in <String>[contacts, groups]) {
      try {
        final List<FileObject> files = await guardSupabase(
          // One photo per contact or group (a replaced one is deleted).
          () => _storage.list(
            path: '$uid/$folder',
            searchOptions: const SearchOptions(limit: 10000),
          ),
        );
        if (files.isNotEmpty) {
          await guardSupabase(
            () => _storage.remove(<String>[
              for (final FileObject f in files) '$uid/$folder/${f.name}',
            ]),
          );
        }
      } on AppException {
        // Left behind, like a profile photo that could not be removed.
      }
    }
    _loads.clear();
    try {
      final Directory local = Directory(
        p.join((await _documents()).path, 'photos', uid),
      );
      if (await local.exists()) await local.delete(recursive: true);
    } on FileSystemException {
      // The app's own folder; nothing else can be done about it here.
    }
  }

  Future<File?> _load(String path) async {
    try {
      final File local = await _local(path);
      if (await local.exists()) return local;
      final Uint8List bytes = await guardSupabase(
        () => _storage.download(path),
      );
      return await _keep(path, bytes);
    } on Object {
      // Offline, signed out or a disk error: the initial shows instead.
      return null;
    }
  }

  Future<File> _keep(String path, Uint8List bytes) async {
    final File local = await _local(path);
    await local.parent.create(recursive: true);
    return local.writeAsBytes(bytes, flush: true);
  }

  Future<File> _local(String path) async => File(
    p.joinAll(<String>[
      (await _documents()).path,
      'photos',
      ...path.split('/'),
    ]),
  );

  StorageFileApi get _storage {
    final SupabaseClient? client = _client;
    if (client == null) throw AuthFailure.sessionExpired;
    return client.storage.from(bucket);
  }
}
