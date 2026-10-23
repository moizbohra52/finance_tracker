import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/savings_goal.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SavingsGoalRepository {
  SavingsGoalRepository(
    this._supabaseClient, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _syncEngine = syncEngine;

  final SupabaseClient _supabaseClient;
  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  Future<List<SavingsGoal>> getSavingsGoals() async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'savings_goals',
        where: 'deleted_at IS NULL',
        orderBy: 'created_at ASC',
      );
      return data.map(SavingsGoalModel.fromJson).toList();
    }

    return guardSupabase(() async {
      final List<Map<String, dynamic>> data = await _supabaseClient
          .from('savings_goals')
          .select()
          .isFilter('deleted_at', null)
          .order('created_at');
      return data.map(SavingsGoalModel.fromJson).toList();
    });
  }

  /// Upserts on the client-generated id, so a retried create never duplicates.
  Future<void> createSavingsGoal(SavingsGoal goal) async {
    if (_db != null) {
      final Map<String, dynamic> json = SavingsGoalModel.toJson(goal);
      await _db.db.insert('savings_goals', <String, dynamic>{
        ...json,
        'created_at': goal.createdAt.toIso8601String(),
        'updated_at': goal.updatedAt.toIso8601String(),
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'savings_goals',
          entityId: goal.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('savings_goals')
          .upsert(
            insertPayload(_supabaseClient, SavingsGoalModel.toJson(goal)),
          );
    });
  }

  Future<void> updateSavingsGoal(SavingsGoal goal) async {
    if (_db != null) {
      final Map<String, dynamic> json = SavingsGoalModel.toJson(goal);
      await _db.db.update(
        'savings_goals',
        <String, dynamic>{
          ...json,
          'updated_at': goal.updatedAt.toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: <Object>[goal.id],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.update,
          entity: 'savings_goals',
          entityId: goal.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('savings_goals')
          .update(updatePayload(SavingsGoalModel.toJson(goal)))
          .eq('id', goal.id);
    });
  }

  Future<void> deleteSavingsGoal(String goalId) async {
    if (_db != null) {
      final String now = DateTime.now().toUtc().toIso8601String();
      await _db.db.update(
        'savings_goals',
        <String, dynamic>{'deleted_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[goalId],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.delete,
          entity: 'savings_goals',
          entityId: goalId,
          payload: tombstone(),
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('savings_goals')
          .update(tombstone())
          .eq('id', goalId);
    });
  }
}
