import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionRepository {
  TransactionRepository(
    this._supabaseClient, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _syncEngine = syncEngine;

  final SupabaseClient _supabaseClient;
  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  /// Types the app can parse and display. Other rows the schema allows
  /// (khata 'credit'/'debit', plain 'adjustment') are excluded rather than
  /// crashing the list.
  static const List<String> _knownTypes = <String>[
    'income',
    'expense',
    'transfer_in',
    'transfer_out',
    'payment_received',
    'payment_made',
    'opening_balance',
  ];

  static final RegExp _filterSyntax = RegExp(r'[,()*%_\\"]');

  /// Newest first. [search] matches the note or description.
  Future<List<Transaction>> getTransactions({
    String? accountId,
    String? categoryId,
    String? contactId,
    TransactionType? type,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) async {
    if (_db != null) {
      final List<String> whereClauses = <String>[
        'deleted_at IS NULL',
        'type IN (${_knownTypes.map((t) => "'$t'").join(', ')})',
      ];
      final List<Object> whereArgs = <Object>[];

      if (accountId != null) {
        whereClauses.add('account_id = ?');
        whereArgs.add(accountId);
      }
      if (categoryId != null) {
        whereClauses.add('category_id = ?');
        whereArgs.add(categoryId);
      }
      if (contactId != null) {
        whereClauses.add('contact_id = ?');
        whereArgs.add(contactId);
      }
      if (type != null) {
        whereClauses.add('type = ?');
        whereArgs.add(type.name);
      }
      if (startDate != null) {
        whereClauses.add('transaction_date >= ?');
        whereArgs.add(startDate.toUtc().toIso8601String());
      }
      if (endDate != null) {
        whereClauses.add('transaction_date <= ?');
        whereArgs.add(endDate.toUtc().toIso8601String());
      }
      final String term = (search ?? '').replaceAll(_filterSyntax, ' ').trim();
      if (term.isNotEmpty) {
        whereClauses.add('(note LIKE ? OR description LIKE ?)');
        whereArgs.add('%$term%');
        whereArgs.add('%$term%');
      }

      final List<Map<String, dynamic>> data = await _db.db.query(
        'transactions',
        where: whereClauses.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'transaction_date DESC',
        limit: limit,
        offset: offset,
      );
      return data
          .map(
            (Map<String, dynamic> json) =>
                TransactionModel.fromJson(json).toEntity(),
          )
          .toList();
    }

    return guardSupabase(() async {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _supabaseClient
          .from('transactions')
          .select()
          .isFilter('deleted_at', null)
          .inFilter('type', _knownTypes);

      if (accountId != null) query = query.eq('account_id', accountId);
      if (categoryId != null) query = query.eq('category_id', categoryId);
      if (contactId != null) query = query.eq('contact_id', contactId);
      if (type != null) query = query.eq('type', type.name);
      if (startDate != null) {
        query = query.gte(
          'transaction_date',
          startDate.toUtc().toIso8601String(),
        );
      }
      if (endDate != null) {
        query = query.lte(
          'transaction_date',
          endDate.toUtc().toIso8601String(),
        );
      }
      // Characters with meaning inside a PostgREST or() filter are dropped.
      final String term = (search ?? '').replaceAll(_filterSyntax, ' ').trim();
      if (term.isNotEmpty) {
        query = query.or('note.ilike.%$term%,description.ilike.%$term%');
      }

      final List<Map<String, dynamic>> data = await query
          .order('transaction_date', ascending: false)
          .range(offset, offset + limit - 1);
      return data
          .map(
            (Map<String, dynamic> json) =>
                TransactionModel.fromJson(json).toEntity(),
          )
          .toList();
    });
  }

  /// Every non-deleted transaction (optionally for one account), paged
  /// internally. Balances are derived from the full history.
  Future<List<Transaction>> getAllTransactions({
    String? accountId,
    DateTime? start,
    DateTime? end,
  }) async {
    if (_db != null) {
      return getTransactions(
        accountId: accountId,
        startDate: start,
        endDate: end?.subtract(const Duration(milliseconds: 1)),
        limit: 100000,
      );
    }

    const int pageSize = 500;
    final List<Transaction> all = <Transaction>[];
    while (true) {
      final List<Transaction> page = await getTransactions(
        accountId: accountId,
        startDate: start,
        endDate: end?.subtract(const Duration(milliseconds: 1)),
        limit: pageSize,
        offset: all.length,
      );
      all.addAll(page);
      if (page.length < pageSize) return all;
    }
  }

  Future<Transaction> getTransactionById(String transactionId) async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object>[transactionId],
        limit: 1,
      );
      if (data.isNotEmpty) {
        return TransactionModel.fromJson(data.first).toEntity();
      }
    }

    return guardSupabase(() async {
      final Map<String, dynamic> response = await _supabaseClient
          .from('transactions')
          .select()
          .eq('id', transactionId)
          .single();
      return TransactionModel.fromJson(response).toEntity();
    });
  }

  /// Upserts on the client-generated id, so a retried create never duplicates.
  ///
  /// With [onlyIfAbsent] an existing row with the same id is left untouched
  /// (used for generated transactions, so a re-run never overwrites a row the
  /// user has since edited).
  Future<void> createTransaction(
    Transaction transaction, {
    bool onlyIfAbsent = false,
  }) async {
    if (_db != null) {
      if (onlyIfAbsent) {
        final List<Map<String, dynamic>> existing = await _db.db.query(
          'transactions',
          where: 'id = ?',
          whereArgs: <Object>[transaction.id],
          limit: 1,
        );
        if (existing.isNotEmpty) return;
      }

      final TransactionModel model = TransactionModel.fromEntity(transaction);
      final Map<String, dynamic> json = model.toJson();
      await _db.db.insert('transactions', <String, dynamic>{
        ...json,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'transactions',
          entityId: transaction.id,
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
          .from('transactions')
          .upsert(
            insertPayload(
              _supabaseClient,
              TransactionModel.fromEntity(transaction).toJson(),
            ),
            ignoreDuplicates: onlyIfAbsent,
          );
    });
  }

  Future<void> updateTransaction(Transaction transaction) async {
    if (_db != null) {
      final TransactionModel model = TransactionModel.fromEntity(transaction);
      final Map<String, dynamic> json = model.toJson();
      await _db.db.update(
        'transactions',
        <String, dynamic>{...json, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[transaction.id],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.update,
          entity: 'transactions',
          entityId: transaction.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('transactions')
          .update(
            updatePayload(TransactionModel.fromEntity(transaction).toJson()),
          )
          .eq('id', transaction.id);
    });
  }

  Future<void> deleteTransaction(String transactionId) async {
    if (_db != null) {
      final String now = DateTime.now().toUtc().toIso8601String();
      await _db.db.update(
        'transactions',
        <String, dynamic>{'deleted_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[transactionId],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.delete,
          entity: 'transactions',
          entityId: transactionId,
          payload: tombstone(),
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('transactions')
          .update(tombstone())
          .eq('id', transactionId);
    });
  }
}
