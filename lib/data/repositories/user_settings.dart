import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's user_settings row.
class UserSettingsRepository {
  UserSettingsRepository(
    this._client, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _syncEngine = syncEngine;

  final SupabaseClient _client;
  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  String? get _userId => _client.auth.currentUser?.id;

  Future<UserSettings> fetch() async {
    final String? uid = _userId;

    if (_db != null && uid != null) {
      final List<Map<String, dynamic>> rows = await _db.db.query(
        'user_settings',
        where: 'user_id = ?',
        whereArgs: <Object>[uid],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return UserSettings.fromJson(rows.first);
      }
    }

    // Attempt remote fetch
    try {
      if (uid == null) throw AuthFailure.sessionExpired;
      final Map<String, dynamic> row = await _client
          .from('user_settings')
          .select(UserSettings.columns)
          .eq('user_id', uid)
          .single();

      final UserSettings settings = UserSettings.fromJson(row);
      // Cache locally
      if (_db != null) {
        await _db.db.insert('user_settings', <String, dynamic>{
          'id': uid,
          'user_id': uid,
          ...settings.toJson(),
          'sync_status': 'synced',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return settings;
    } on Object catch (_) {
      // If offline and nothing cached, return standard defaults
      return const UserSettings(
        dateFormat: null,
        numberFormat: null,
        firstDayOfWeek: null,
        languageCode: null,
        defaultAccountId: null,
      );
    }
  }

  /// Writes all editable preference columns.
  Future<UserSettings> save(UserSettings settings) async {
    final String? uid = _userId;
    if (_db != null && uid != null) {
      final Map<String, dynamic> json = settings.toJson();
      await _db.db.insert('user_settings', <String, dynamic>{
        'id': uid,
        'user_id': uid,
        ...json,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.update,
          entity: 'user_settings',
          entityId: uid,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return settings;
    }

    return guardSupabase(() async {
      if (uid == null) throw AuthFailure.sessionExpired;
      final Map<String, dynamic> row = await _client
          .from('user_settings')
          .update(settings.toJson())
          .eq('user_id', uid)
          .select(UserSettings.columns)
          .single();
      return UserSettings.fromJson(row);
    });
  }
}
