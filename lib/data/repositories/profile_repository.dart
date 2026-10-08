import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's profile row and avatar object.
class ProfileRepository {
  ProfileRepository(
    this._client, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _syncEngine = syncEngine;

  final SupabaseClient _client;
  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  static const String avatarBucket = 'avatars';

  /// How long a shown avatar link stays valid.
  static const Duration avatarLinkLifetime = Duration(hours: 1);

  String? get _userId => _client.auth.currentUser?.id;

  Future<Profile> fetchProfile() async {
    final String? uid = _userId;

    // Check local database first if available
    if (_db != null && uid != null) {
      final List<Map<String, dynamic>> rows = await _db.db.query(
        'profiles',
        where: 'id = ?',
        whereArgs: <Object>[uid],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        // Return local if offline or as fast cache
        final Profile localProfile = Profile.fromJson(rows.first);
        // If online, refresh in background or fetch
        try {
          final Map<String, dynamic> row = await _client
              .from('profiles')
              .select(Profile.columns)
              .eq('id', uid)
              .single();
          final Profile remote = Profile.fromJson(row);
          await _cacheProfile(remote);
          return remote;
        } on Object catch (_) {
          return localProfile;
        }
      }
    }

    try {
      if (uid == null) throw AuthFailure.sessionExpired;
      final Map<String, dynamic> row = await _client
          .from('profiles')
          .select(Profile.columns)
          .eq('id', uid)
          .single();
      final Profile profile = Profile.fromJson(row);
      await _cacheProfile(profile);
      return profile;
    } on Object catch (_) {
      return Profile(id: uid ?? '', currencyCode: 'INR');
    }
  }

  Future<void> _cacheProfile(Profile profile) async {
    if (_db != null && profile.id.isNotEmpty) {
      final String now = DateTime.now().toUtc().toIso8601String();
      await _db.db.insert('profiles', <String, dynamic>{
        'id': profile.id,
        'full_name': profile.fullName,
        'mobile': profile.mobile,
        'avatar_url': profile.avatarPath,
        'currency_code': profile.currencyCode ?? 'INR',
        'timezone': profile.timezone,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Only the fields that are passed change.
  Future<Profile> updateProfile({
    String? fullName,
    String? mobile,
    bool clearMobile = false,
    String? currencyCode,
    String? timezone,
    String? avatarPath,
    bool clearAvatar = false,
  }) async {
    final String? uid = _userId;
    final Map<String, dynamic> updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (clearMobile) {
      updates['mobile'] = null;
    } else if (mobile != null) {
      updates['mobile'] = mobile;
    }
    if (currencyCode != null) updates['currency_code'] = currencyCode;
    if (timezone != null) updates['timezone'] = timezone;
    if (clearAvatar) {
      updates['avatar_url'] = null;
    } else if (avatarPath != null) {
      updates['avatar_url'] = avatarPath;
    }

    if (updates.isEmpty) return await fetchProfile();

    if (_db != null && uid != null) {
      await _db.db.update(
        'profiles',
        <String, dynamic>{...updates, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[uid],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.update,
          entity: 'profiles',
          entityId: uid,
          payload: updates,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
    }

    try {
      if (uid == null) throw AuthFailure.sessionExpired;
      final Map<String, dynamic> row = await _client
          .from('profiles')
          .update(updates)
          .eq('id', uid)
          .select(Profile.columns)
          .single();
      final Profile profile = Profile.fromJson(row);
      await _cacheProfile(profile);
      return profile;
    } on Object catch (_) {
      return await fetchProfile();
    }
  }

  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) => guardSupabase(() async {
    final String? uid = _userId;
    if (uid == null) throw AuthFailure.sessionExpired;
    final String path =
        '$uid/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage
        .from(avatarBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return path;
  });

  Future<String> avatarLink(String path) => guardSupabase(
    () => _client.storage
        .from(avatarBucket)
        .createSignedUrl(path, avatarLinkLifetime.inSeconds),
  );

  Future<void> removeAvatar(String path) => guardSupabase(
    () => _client.storage.from(avatarBucket).remove(<String>[path]),
  );
}
