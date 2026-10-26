import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/savings_contribution.dart';
import 'package:finance_tracker/data/models/savings_goal.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/domain/services/savings_split.dart';
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

  /// Each goal carries the sum of its live contributions, from incomes that
  /// still exist; summed in Dart so money never goes through SQL arithmetic.
  Future<List<SavingsGoal>> getSavingsGoals() async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'savings_goals',
        where: 'deleted_at IS NULL',
        orderBy: 'created_at ASC',
      );
      final List<Map<String, dynamic>> rows = await _db.db.rawQuery(
        'SELECT c.* FROM savings_contributions c '
        'JOIN transactions t ON t.id = c.transaction_id '
        'WHERE c.deleted_at IS NULL AND t.deleted_at IS NULL',
      );
      return _withContributions(
        data,
        rows.map(SavingsContributionModel.fromJson),
      );
    }

    return guardSupabase(() async {
      final List<Map<String, dynamic>> data = await _supabaseClient
          .from('savings_goals')
          .select()
          .isFilter('deleted_at', null)
          .order('created_at');
      final List<Map<String, dynamic>> rows = await _supabaseClient
          .from('savings_contributions')
          .select()
          .isFilter('deleted_at', null);
      List<SavingsContribution> live = rows
          .map(SavingsContributionModel.fromJson)
          .toList();
      if (live.isNotEmpty) {
        // shortcut: one IN query and the default 1000-row page; page it if a
        // user ever holds that many contributions.
        final List<Map<String, dynamic>> alive = await _supabaseClient
            .from('transactions')
            .select('id')
            .inFilter(
              'id',
              <String>{
                for (final SavingsContribution c in live) c.transactionId,
              }.toList(),
            )
            .isFilter('deleted_at', null);
        final Set<String> ids = <String>{
          for (final Map<String, dynamic> r in alive) r['id'] as String,
        };
        live = live
            .where((SavingsContribution c) => ids.contains(c.transactionId))
            .toList();
      }
      return _withContributions(data, live);
    });
  }

  static List<SavingsGoal> _withContributions(
    List<Map<String, dynamic>> goals,
    Iterable<SavingsContribution> live,
  ) {
    final Map<String, Decimal> sums = SavingsSplit.sumByGoal(live);
    return <SavingsGoal>[
      for (final Map<String, dynamic> row in goals)
        SavingsGoalModel.fromJson(<String, dynamic>{
          ...row,
          'contributed_amount': sums[row['id']]?.toString(),
        }),
    ];
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

  /// Also soft-deletes the goal's contributions, so no total outlives it.
  Future<void> deleteSavingsGoal(String goalId) async {
    if (_db != null) {
      final DateTime now = DateTime.now();
      final String stamp = now.toUtc().toIso8601String();
      await _db.db.transaction((txn) async {
        await txn.update(
          'savings_goals',
          <String, dynamic>{'deleted_at': stamp, 'sync_status': 'pending'},
          where: 'id = ?',
          whereArgs: <Object>[goalId],
        );
        await _enqueueDelete(txn, 'savings_goals', goalId, now);
        final List<Map<String, dynamic>> live = await txn.query(
          'savings_contributions',
          columns: <String>['id'],
          where: 'goal_id = ? AND deleted_at IS NULL',
          whereArgs: <Object>[goalId],
        );
        for (final Map<String, dynamic> r in live) {
          final String id = r['id'] as String;
          await txn.update(
            'savings_contributions',
            <String, dynamic>{'deleted_at': stamp, 'sync_status': 'pending'},
            where: 'id = ?',
            whereArgs: <Object>[id],
          );
          await _enqueueDelete(txn, 'savings_contributions', id, now);
        }
      });
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('savings_goals')
          .update(tombstone())
          .eq('id', goalId);
      await _supabaseClient
          .from('savings_contributions')
          .update(tombstone())
          .eq('goal_id', goalId)
          .isFilter('deleted_at', null);
    });
  }

  static Future<void> _enqueueDelete(
    DatabaseExecutor txn,
    String entity,
    String entityId,
    DateTime now,
  ) => txn.insert(
    'sync_queue',
    SyncQueueItem(
      operation: SyncOperation.delete,
      entity: entity,
      entityId: entityId,
      payload: tombstone(),
      createdAt: now,
    ).toRow(),
  );
}
