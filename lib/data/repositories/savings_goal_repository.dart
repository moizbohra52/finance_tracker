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

  /// Each goal carries the sums of its live contributions, from incomes and
  /// added by hand; summed in Dart so money never goes through SQL arithmetic.
  Future<List<SavingsGoal>> getSavingsGoals() async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'savings_goals',
        where: 'deleted_at IS NULL',
        orderBy: 'created_at ASC',
      );
      final List<Map<String, dynamic>> rows = await _db.db.rawQuery(
        'SELECT c.* $_liveContributions',
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
      return _withContributions(data, (await _remoteLive()).$1);
    });
  }

  /// Live contributions: not deleted, and either added by hand or part of an
  /// income that still exists (and has been pulled).
  static const String _liveContributions =
      'FROM savings_contributions c '
      'LEFT JOIN transactions t ON t.id = c.transaction_id '
      'WHERE c.deleted_at IS NULL AND (c.transaction_id IS NULL OR '
      '(t.id IS NOT NULL AND t.deleted_at IS NULL))';

  /// [_liveContributions] read from the server, with the incomes they come
  /// from by id.
  Future<(List<SavingsContribution>, Map<String, Map<String, dynamic>>)>
  _remoteLive({String? goalId}) async {
    PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _supabaseClient
        .from('savings_contributions')
        .select()
        .isFilter('deleted_at', null);
    if (goalId != null) query = query.eq('goal_id', goalId);
    final List<SavingsContribution> live = (await query)
        .map(SavingsContributionModel.fromJson)
        .toList();
    final Set<String> ids = <String>{
      for (final SavingsContribution c in live)
        if (c.transactionId != null) c.transactionId!,
    };
    if (ids.isEmpty) return (live, <String, Map<String, dynamic>>{});
    // shortcut: one IN query and the default 1000-row page; page it if a
    // user ever holds that many contributions.
    final List<Map<String, dynamic>> alive = await _supabaseClient
        .from('transactions')
        .select('id, transaction_date, description, note')
        .inFilter('id', ids.toList())
        .isFilter('deleted_at', null);
    final Map<String, Map<String, dynamic>> incomes =
        <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> r in alive) r['id'] as String: r,
        };
    return (
      live
          .where(
            (SavingsContribution c) =>
                c.transactionId == null || incomes.containsKey(c.transactionId),
          )
          .toList(),
      incomes,
    );
  }

  static List<SavingsGoal> _withContributions(
    List<Map<String, dynamic>> goals,
    Iterable<SavingsContribution> live,
  ) {
    final Map<String, Decimal> fromIncome = SavingsSplit.sumByGoal(
      live.where((SavingsContribution c) => c.isFromIncome),
    );
    final Map<String, Decimal> byHand = SavingsSplit.sumByGoal(
      live.where((SavingsContribution c) => !c.isFromIncome),
    );
    return <SavingsGoal>[
      for (final Map<String, dynamic> row in goals)
        SavingsGoalModel.fromJson(<String, dynamic>{
          ...row,
          'contributed_amount': fromIncome[row['id']]?.toString(),
          'added_amount': byHand[row['id']]?.toString(),
        }),
    ];
  }

  /// Money added to a goal by hand: a contribution without an income. The id
  /// is generated once per Add money sheet, so a retried save upserts the
  /// same row instead of adding twice.
  Future<void> addMoney(SavingsContribution contribution) async {
    final Map<String, dynamic> json = SavingsContributionModel.toJson(
      contribution,
    );
    if (_db != null) {
      await _db.db.insert('savings_contributions', <String, dynamic>{
        ...json,
        'created_at': contribution.createdAt.toUtc().toIso8601String(),
        'updated_at': contribution.updatedAt.toUtc().toIso8601String(),
        'deleted_at': null,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'savings_contributions',
          entityId: contribution.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('savings_contributions')
          .upsert(insertPayload(_supabaseClient, json));
    });
  }

  /// Soft-deletes one history entry added by hand. An income's part is left
  /// alone: it follows its income.
  Future<void> deleteContribution(String id) async {
    if (_db != null) {
      final DateTime now = DateTime.now();
      await _db.db.transaction((txn) async {
        final int changed = await txn.update(
          'savings_contributions',
          <String, dynamic>{
            'deleted_at': now.toUtc().toIso8601String(),
            'sync_status': 'pending',
          },
          where: 'id = ? AND transaction_id IS NULL',
          whereArgs: <Object>[id],
        );
        if (changed > 0) {
          await _enqueueDelete(txn, 'savings_contributions', id, now);
        }
      });
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('savings_contributions')
          .update(tombstone())
          .eq('id', id)
          .isFilter('transaction_id', null);
    });
  }

  /// [goalId]'s history, newest first, [limit] entries from [offset]: money
  /// added by hand and the parts of incomes that still exist.
  Future<List<SavingsHistoryEntry>> getHistory(
    String goalId, {
    int offset = 0,
    int limit = 50,
  }) async {
    if (_db != null) {
      // Both dates are stored as UTC ISO text, so they sort together.
      final List<Map<String, dynamic>> rows = await _db.db.rawQuery(
        'SELECT c.*, t.transaction_date AS income_date, '
        't.description AS income_description, t.note AS income_note '
        '$_liveContributions AND c.goal_id = ? '
        'ORDER BY COALESCE(c.added_at, t.transaction_date) DESC, c.id '
        'LIMIT ? OFFSET ?',
        <Object>[goalId, limit, offset],
      );
      return rows.map(_historyEntry).toList();
    }

    return guardSupabase(() async {
      final (
        List<SavingsContribution> live,
        Map<String, Map<String, dynamic>> incomes,
      ) = await _remoteLive(
        goalId: goalId,
      );
      final List<SavingsHistoryEntry> all = <SavingsHistoryEntry>[
        for (final SavingsContribution c in live)
          _historyEntry(<String, dynamic>{
            ...SavingsContributionModel.toJson(c),
            'created_at': c.createdAt.toUtc().toIso8601String(),
            'updated_at': c.updatedAt.toUtc().toIso8601String(),
            'income_date': incomes[c.transactionId]?['transaction_date'],
            'income_description': incomes[c.transactionId]?['description'],
            'income_note': incomes[c.transactionId]?['note'],
          }),
      ]..sort(_newestFirst);
      // shortcut: pages in memory after reading the goal's whole history;
      // page on the server if a goal ever holds thousands of entries.
      return all.skip(offset).take(limit).toList();
    });
  }

  static int _newestFirst(SavingsHistoryEntry a, SavingsHistoryEntry b) {
    final int byDate = b.date.compareTo(a.date);
    return byDate != 0
        ? byDate
        : a.contribution.id.compareTo(b.contribution.id);
  }

  static SavingsHistoryEntry _historyEntry(Map<String, dynamic> row) {
    final SavingsContribution c = SavingsContributionModel.fromJson(row);
    String? text(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    final Object? incomeDate = row['income_date'];
    return SavingsHistoryEntry(
      contribution: c,
      date:
          c.addedAt ??
          (incomeDate is String
              ? DateTime.parse(incomeDate).toLocal()
              : c.createdAt.toLocal()),
      incomeTitle: c.isFromIncome
          ? text(row['income_description']) ?? text(row['income_note'])
          : null,
    );
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
