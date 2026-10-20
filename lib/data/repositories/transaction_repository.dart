import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/entities/transaction_summary.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
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

  /// Computes the aggregate totals (total inflow, total outflow, and total count)
  /// for all transactions matching the given filters, without pagination.
  Future<TransactionSummary> getTransactionSummary({
    String? accountId,
    String? categoryId,
    String? contactId,
    TransactionType? type,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
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

      final List<Map<String, dynamic>> rows = await _db.db.query(
        'transactions',
        columns: <String>['type', 'amount', 'transfer_id'],
        where: whereClauses.join(' AND '),
        whereArgs: whereArgs,
      );

      Decimal inflow = Decimal.zero;
      Decimal outflow = Decimal.zero;

      for (final Map<String, dynamic> row in rows) {
        final String rawType = row['type'] as String;
        final String rawAmount = row['amount'] as String;
        final Decimal amount = Decimal.tryParse(rawAmount) ?? Decimal.zero;

        final bool isInflow = rawType == 'income' ||
            rawType == 'transfer_in' ||
            rawType == 'adjustment_in' ||
            rawType == 'payment_received' ||
            rawType == 'opening_balance';

        final bool isOutflow = rawType == 'expense' ||
            rawType == 'transfer_out' ||
            rawType == 'adjustment_out' ||
            rawType == 'payment_made';

        if (isInflow) {
          inflow += amount;
        } else if (isOutflow) {
          outflow += amount;
        }
      }

      return TransactionSummary(
        totalInflow: inflow,
        totalOutflow: outflow,
        totalCount: rows.length,
      );
    }

    return guardSupabase(() async {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _supabaseClient
          .from('transactions')
          .select('type, amount, transfer_id')
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
      final String term = (search ?? '').replaceAll(_filterSyntax, ' ').trim();
      if (term.isNotEmpty) {
        query = query.or('note.ilike.%$term%,description.ilike.%$term%');
      }

      final List<Map<String, dynamic>> rows = await query;
      Decimal inflow = Decimal.zero;
      Decimal outflow = Decimal.zero;

      for (final Map<String, dynamic> row in rows) {
        final String rawType = row['type'] as String;
        final Object? rawAmount = row['amount'];
        final Decimal amount =
            Decimal.tryParse(rawAmount?.toString() ?? '0') ?? Decimal.zero;

        final bool isInflow = rawType == 'income' ||
            rawType == 'transfer_in' ||
            rawType == 'adjustment_in' ||
            rawType == 'payment_received' ||
            rawType == 'opening_balance';

        final bool isOutflow = rawType == 'expense' ||
            rawType == 'transfer_out' ||
            rawType == 'adjustment_out' ||
            rawType == 'payment_made';

        if (isInflow) {
          inflow += amount;
        } else if (isOutflow) {
          outflow += amount;
        }
      }

      return TransactionSummary(
        totalInflow: inflow,
        totalOutflow: outflow,
        totalCount: rows.length,
      );
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
  // --- Transfers (docs/05_FINANCIAL_LOGIC.md) ---

  /// Both live legs of a transfer, or null when it was deleted or is
  /// incomplete.
  Future<TransferLegs?> getTransfer(String transferId) async {
    if (_db != null) {
      final List<Map<String, dynamic>> rows = await _db.db.query(
        'transactions',
        where: 'transfer_id = ? AND deleted_at IS NULL',
        whereArgs: <Object>[transferId],
      );
      return TransferLegs.fromRows(
        rows.map(
          (Map<String, dynamic> r) => TransactionModel.fromJson(r).toEntity(),
        ),
      );
    }

    return guardSupabase(() async {
      final List<Map<String, dynamic>> rows = await _supabaseClient
          .from('transactions')
          .select()
          .eq('transfer_id', transferId)
          .isFilter('deleted_at', null);
      return TransferLegs.fromRows(
        rows.map(
          (Map<String, dynamic> r) => TransactionModel.fromJson(r).toEntity(),
        ),
      );
    });
  }

  /// Records both legs together, so a transfer is never half-written:
  /// locally in one database transaction with both queue items, remotely in
  /// one upsert. Ids are client-generated, so a retry upserts the same rows.
  ///
  /// With [replacing], that transfer's legs are tombstoned in the same step
  /// (an edit that cannot update in place, see
  /// [TransferLegs.canUpdateInPlace]).
  Future<void> createTransfer(TransferLegs legs, {String? replacing}) async {
    if (_db != null) {
      final DateTime now = DateTime.now();
      await _db.db.transaction((txn) async {
        if (replacing != null) await _tombstoneTransfer(txn, replacing, now);
        for (final Transaction leg in <Transaction>[
          legs.outgoing,
          legs.incoming,
        ]) {
          final Map<String, dynamic> json = TransactionModel.fromEntity(
            leg,
          ).toJson();
          await txn.insert('transactions', <String, dynamic>{
            ...json,
            'sync_status': 'pending',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await txn.insert(
            'sync_queue',
            SyncQueueItem(
              operation: SyncOperation.create,
              entity: 'transactions',
              entityId: leg.id,
              payload: json,
              createdAt: now,
            ).toRow(),
          );
        }
      });
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      if (replacing != null) {
        await _supabaseClient
            .from('transactions')
            .update(tombstone())
            .eq('transfer_id', replacing);
      }
      await _supabaseClient.from('transactions').upsert(<Map<String, dynamic>>[
        for (final Transaction leg in <Transaction>[
          legs.outgoing,
          legs.incoming,
        ])
          insertPayload(
            _supabaseClient,
            TransactionModel.fromEntity(leg).toJson(),
          ),
      ]);
    });
  }

  /// Updates both legs of an existing transfer (amount, date, note, or an
  /// account change allowed by [TransferLegs.canUpdateInPlace]). The
  /// outgoing leg is written and queued first.
  Future<void> updateTransfer(TransferLegs legs) async {
    final List<Transaction> ordered = <Transaction>[
      legs.outgoing,
      legs.incoming,
    ];
    if (_db != null) {
      final DateTime now = DateTime.now();
      await _db.db.transaction((txn) async {
        for (final Transaction leg in ordered) {
          final Map<String, dynamic> json = TransactionModel.fromEntity(
            leg,
          ).toJson();
          await txn.update(
            'transactions',
            <String, dynamic>{...json, 'sync_status': 'pending'},
            where: 'id = ?',
            whereArgs: <Object>[leg.id],
          );
          await txn.insert(
            'sync_queue',
            SyncQueueItem(
              operation: SyncOperation.update,
              entity: 'transactions',
              entityId: leg.id,
              payload: json,
              createdAt: now,
            ).toRow(),
          );
        }
      });
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      for (final Transaction leg in ordered) {
        await _supabaseClient
            .from('transactions')
            .update(updatePayload(TransactionModel.fromEntity(leg).toJson()))
            .eq('id', leg.id);
      }
    });
  }

  /// Soft-deletes both legs of a transfer together.
  Future<void> deleteTransfer(String transferId) async {
    if (_db != null) {
      await _db.db.transaction(
        (txn) => _tombstoneTransfer(txn, transferId, DateTime.now()),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await guardSupabase(() async {
      await _supabaseClient
          .from('transactions')
          .update(tombstone())
          .eq('transfer_id', transferId);
    });
  }

  /// Tombstones the live legs of [transferId] and queues their deletes.
  static Future<void> _tombstoneTransfer(
    DatabaseExecutor txn,
    String transferId,
    DateTime now,
  ) async {
    final List<Map<String, dynamic>> legs = await txn.query(
      'transactions',
      columns: <String>['id'],
      where: 'transfer_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[transferId],
    );
    final String deletedAt = now.toUtc().toIso8601String();
    for (final Map<String, dynamic> leg in legs) {
      final String id = leg['id'] as String;
      await txn.update(
        'transactions',
        <String, dynamic>{'deleted_at': deletedAt, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
      await txn.insert(
        'sync_queue',
        SyncQueueItem(
          operation: SyncOperation.delete,
          entity: 'transactions',
          entityId: id,
          payload: tombstone(),
          createdAt: now,
        ).toRow(),
      );
    }
  }
}
