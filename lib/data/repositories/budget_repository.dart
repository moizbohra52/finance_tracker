import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/budget.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BudgetRepository {
  BudgetRepository(
    this._supabaseClient, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _syncEngine = syncEngine;

  final SupabaseClient _supabaseClient;
  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  Future<List<Budget>> getBudgets() async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'budgets',
        where: 'deleted_at IS NULL',
        orderBy: 'created_at ASC',
      );
      return data.map(BudgetModel.fromJson).toList();
    }

    return guardSupabase(() async {
      final List<Map<String, dynamic>> data = await _supabaseClient
          .from('budgets')
          .select()
          .isFilter('deleted_at', null)
          .order('created_at');
      return data.map(BudgetModel.fromJson).toList();
    });
  }

  /// Upserts on the client-generated id, so a retried create never duplicates.
  Future<void> createBudget(Budget budget) async {
    if (_db != null) {
      final Map<String, dynamic> json = BudgetModel.toJson(budget);
      await _db.db.insert('budgets', <String, dynamic>{
        ...json,
        'alert_75': budget.alert75 ? 1 : 0,
        'alert_90': budget.alert90 ? 1 : 0,
        'alert_100': budget.alert100 ? 1 : 0,
        'created_at': budget.createdAt.toIso8601String(),
        'updated_at': budget.updatedAt.toIso8601String(),
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'budgets',
          entityId: budget.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('budgets')
          .upsert(insertPayload(_supabaseClient, BudgetModel.toJson(budget)));
    });
  }

  Future<void> updateBudget(Budget budget) async {
    if (_db != null) {
      final Map<String, dynamic> json = BudgetModel.toJson(budget);
      await _db.db.update(
        'budgets',
        <String, dynamic>{
          ...json,
          'alert_75': budget.alert75 ? 1 : 0,
          'alert_90': budget.alert90 ? 1 : 0,
          'alert_100': budget.alert100 ? 1 : 0,
          'updated_at': budget.updatedAt.toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: <Object>[budget.id],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.update,
          entity: 'budgets',
          entityId: budget.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('budgets')
          .update(updatePayload(BudgetModel.toJson(budget)))
          .eq('id', budget.id);
    });
  }

  Future<void> deleteBudget(String budgetId) async {
    if (_db != null) {
      final String now = DateTime.now().toUtc().toIso8601String();
      await _db.db.update(
        'budgets',
        <String, dynamic>{'deleted_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[budgetId],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.delete,
          entity: 'budgets',
          entityId: budgetId,
          payload: tombstone(),
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('budgets')
          .update(tombstone())
          .eq('id', budgetId);
    });
  }
}
