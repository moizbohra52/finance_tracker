import 'dart:convert';

import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/reminder.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReminderRepository {
  ReminderRepository(
    this._supabaseClient, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _syncEngine = syncEngine;

  final SupabaseClient _supabaseClient;
  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  /// Every live reminder, soonest first.
  Future<List<Reminder>> getAll() async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'reminders',
        where: 'deleted_at IS NULL',
        orderBy: 'remind_at ASC',
      );
      return data.map(ReminderModel.fromJson).toList();
    }

    return guardSupabase(() async {
      final List<Map<String, dynamic>> data = await _supabaseClient
          .from('reminders')
          .select()
          .isFilter('deleted_at', null)
          .order('remind_at');
      return data.map(ReminderModel.fromJson).toList();
    });
  }

  /// Upserts on the client-generated id, so a retried create never duplicates.
  ///
  /// With [onlyIfAbsent] an existing row with the same id, live or deleted, is
  /// left untouched (generated reminders: a re-run never brings back or
  /// overwrites one the user deleted or changed).
  Future<void> create(Reminder reminder, {bool onlyIfAbsent = false}) async {
    if (_db != null) {
      if (onlyIfAbsent) {
        final List<Map<String, dynamic>> existing = await _db.db.query(
          'reminders',
          columns: <String>['id'],
          where: 'id = ?',
          whereArgs: <Object>[reminder.id],
          limit: 1,
        );
        if (existing.isNotEmpty) return;
      }
      final Map<String, dynamic> json = ReminderModel.toJson(reminder);
      await _db.db.insert('reminders', <String, dynamic>{
        ...json,
        'is_completed': reminder.isCompleted ? 1 : 0,
        'notification_enabled': reminder.notificationEnabled ? 1 : 0,
        'created_at': reminder.createdAt.toUtc().toIso8601String(),
        'updated_at': reminder.updatedAt.toUtc().toIso8601String(),
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'reminders',
          entityId: reminder.id,
          payload: <String, dynamic>{
            ...json,
            if (onlyIfAbsent) '__only_if_absent': true,
          },
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('reminders')
          .upsert(
            insertPayload(_supabaseClient, ReminderModel.toJson(reminder)),
            ignoreDuplicates: onlyIfAbsent,
          );
    });
  }

  /// Edit, complete, snooze and enable/disable all go through here.
  Future<void> update(Reminder reminder) async {
    if (_db != null) {
      final Map<String, dynamic> json = ReminderModel.toJson(reminder);
      await _db.db.update(
        'reminders',
        <String, dynamic>{
          ...json,
          'is_completed': reminder.isCompleted ? 1 : 0,
          'notification_enabled': reminder.notificationEnabled ? 1 : 0,
          'updated_at': reminder.updatedAt.toUtc().toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: <Object>[reminder.id],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.update,
          entity: 'reminders',
          entityId: reminder.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('reminders')
          .update(updatePayload(ReminderModel.toJson(reminder)))
          .eq('id', reminder.id);
    });
  }

  /// Whether this device has pulled the account at least once, so local rows
  /// (deleted ones included) reflect the server and a generated reminder
  /// created only if absent cannot bring back one deleted elsewhere. Without
  /// a local database the server is used directly.
  Future<bool> hasPulled() async {
    final AppDatabase? db = _db;
    return db == null || await db.getMetadata(AppDatabase.pulledKey) != null;
  }

  Map<String, int> _khataBalances = <String, int>{};

  /// Each contact's balance sign at the last reminders load
  /// (KhataDueReminders.plan). Kept in the account's database, so a change
  /// made while the app was closed or pulled from another device is seen.
  Future<Map<String, int>> readKhataBalances() async {
    final AppDatabase? db = _db;
    if (db == null) return _khataBalances;
    final String? raw = await db.getMetadata(AppDatabase.khataDueBalancesKey);
    if (raw == null) return <String, int>{};
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, int>();
  }

  Future<void> saveKhataBalances(Map<String, int> balances) async {
    final AppDatabase? db = _db;
    if (db == null) {
      _khataBalances = balances;
      return;
    }
    await db.setMetadata(AppDatabase.khataDueBalancesKey, jsonEncode(balances));
  }

  Future<void> delete(String id) async {
    if (_db != null) {
      final String now = DateTime.now().toUtc().toIso8601String();
      await _db.db.update(
        'reminders',
        <String, dynamic>{'deleted_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.delete,
          entity: 'reminders',
          entityId: id,
          payload: tombstone(),
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient.from('reminders').update(tombstone()).eq('id', id);
    });
  }
}
