import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountRepository {
  AccountRepository(
    this._supabaseClient, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _syncEngine = syncEngine;

  final SupabaseClient _supabaseClient;
  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  Future<List<Account>> getAccounts() async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'accounts',
        where: 'deleted_at IS NULL',
        orderBy: 'created_at ASC',
      );
      return data
          .map(
            (Map<String, dynamic> json) =>
                AccountModel.fromJson(json).toEntity(),
          )
          .toList();
    }

    return guardSupabase(() async {
      final List<Map<String, dynamic>> data = await _supabaseClient
          .from('accounts')
          .select()
          .isFilter('deleted_at', null)
          .order('created_at');
      return data
          .map(
            (Map<String, dynamic> json) =>
                AccountModel.fromJson(json).toEntity(),
          )
          .toList();
    });
  }

  Future<Account> getAccountById(String accountId) async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'accounts',
        where: 'id = ?',
        whereArgs: <Object>[accountId],
        limit: 1,
      );
      if (data.isNotEmpty) {
        return AccountModel.fromJson(data.first).toEntity();
      }
    }

    return guardSupabase(() async {
      final Map<String, dynamic> response = await _supabaseClient
          .from('accounts')
          .select()
          .eq('id', accountId)
          .single();
      return AccountModel.fromJson(response).toEntity();
    });
  }

  /// Upserts on the client-generated id, so a retried create never duplicates.
  Future<void> createAccount(Account account) async {
    if (_db != null) {
      final AccountModel model = AccountModel.fromEntity(account);
      final Map<String, dynamic> json = model.toJson();
      await _db.db.insert('accounts', <String, dynamic>{
        ...json,
        'is_active': account.isActive ? 1 : 0,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'accounts',
          entityId: account.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('accounts')
          .upsert(
            insertPayload(
              _supabaseClient,
              AccountModel.fromEntity(account).toJson(),
            ),
          );
    });
  }

  Future<void> updateAccount(Account account) async {
    if (_db != null) {
      final AccountModel model = AccountModel.fromEntity(account);
      final Map<String, dynamic> json = model.toJson();
      await _db.db.update(
        'accounts',
        <String, dynamic>{
          ...json,
          'is_active': account.isActive ? 1 : 0,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: <Object>[account.id],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.update,
          entity: 'accounts',
          entityId: account.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('accounts')
          .update(updatePayload(AccountModel.fromEntity(account).toJson()))
          .eq('id', account.id);
    });
  }

  /// Soft delete: transactions reference accounts, so history must survive.
  Future<void> deleteAccount(String accountId) async {
    if (_db != null) {
      final String now = DateTime.now().toUtc().toIso8601String();
      await _db.db.update(
        'accounts',
        <String, dynamic>{'deleted_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[accountId],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.delete,
          entity: 'accounts',
          entityId: accountId,
          payload: tombstone(),
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('accounts')
          .update(tombstone())
          .eq('id', accountId);
    });
  }
}
