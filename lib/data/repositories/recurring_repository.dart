import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/recurring_transaction.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecurringRepository {
  RecurringRepository(
    this._supabaseClient, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _syncEngine = syncEngine;

  final SupabaseClient _supabaseClient;
  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  Future<List<RecurringTransaction>> getAll() async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'recurring_transactions',
        where: 'deleted_at IS NULL',
        orderBy: 'next_run_at ASC',
      );
      return data.map(RecurringTransactionModel.fromJson).toList();
    }

    return guardSupabase(() async {
      final List<Map<String, dynamic>> data = await _supabaseClient
          .from('recurring_transactions')
          .select()
          .isFilter('deleted_at', null)
          .order('next_run_at');
      return data.map(RecurringTransactionModel.fromJson).toList();
    });
  }

  /// Upserts on the client-generated id, so a retried create never duplicates.
  Future<void> create(RecurringTransaction rule) async {
    if (_db != null) {
      final Map<String, dynamic> json = RecurringTransactionModel.toJson(rule);
      await _db.db.insert('recurring_transactions', <String, dynamic>{
        ...json,
        'active': rule.active ? 1 : 0,
        'created_at': rule.createdAt.toIso8601String(),
        'updated_at': rule.updatedAt.toIso8601String(),
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'recurring_transactions',
          entityId: rule.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('recurring_transactions')
          .upsert(
            insertPayload(
              _supabaseClient,
              RecurringTransactionModel.toJson(rule),
            ),
          );
    });
  }

  Future<void> update(RecurringTransaction rule) async {
    if (_db != null) {
      final Map<String, dynamic> json = RecurringTransactionModel.toJson(rule);
      await _db.db.update(
        'recurring_transactions',
        <String, dynamic>{
          ...json,
          'active': rule.active ? 1 : 0,
          'updated_at': rule.updatedAt.toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: <Object>[rule.id],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.update,
          entity: 'recurring_transactions',
          entityId: rule.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('recurring_transactions')
          .update(updatePayload(RecurringTransactionModel.toJson(rule)))
          .eq('id', rule.id);
    });
  }

  Future<void> delete(String id) async {
    if (_db != null) {
      final String now = DateTime.now().toUtc().toIso8601String();
      await _db.db.update(
        'recurring_transactions',
        <String, dynamic>{'deleted_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.delete,
          entity: 'recurring_transactions',
          entityId: id,
          payload: tombstone(),
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('recurring_transactions')
          .update(tombstone())
          .eq('id', id);
    });
  }
}
