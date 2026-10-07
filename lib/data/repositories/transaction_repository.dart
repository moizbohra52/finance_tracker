import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionRepository {
  TransactionRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

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
  }) => guardSupabase(() async {
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
      query = query.lte('transaction_date', endDate.toUtc().toIso8601String());
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

  /// Every non-deleted transaction (optionally for one account), paged
  /// internally. Balances are derived from the full history.
  // ponytail: client-side totals; move to a server-side aggregate if history
  // grows beyond a few thousand rows.
  ///
  /// [start] is inclusive and [end] exclusive, matching report periods.
  Future<List<Transaction>> getAllTransactions({
    String? accountId,
    DateTime? start,
    DateTime? end,
  }) async {
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

  Future<Transaction> getTransactionById(String transactionId) =>
      guardSupabase(() async {
        final Map<String, dynamic> response = await _supabaseClient
            .from('transactions')
            .select()
            .eq('id', transactionId)
            .single();
        return TransactionModel.fromJson(response).toEntity();
      });

  /// Upserts on the client-generated id, so a retried create never duplicates.
  ///
  /// With [onlyIfAbsent] an existing row with the same id is left untouched
  /// (used for generated transactions, so a re-run never overwrites a row the
  /// user has since edited).
  Future<void> createTransaction(
    Transaction transaction, {
    bool onlyIfAbsent = false,
  }) => guardSupabase(() async {
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

  Future<void> updateTransaction(Transaction transaction) =>
      guardSupabase(() async {
        await _supabaseClient
            .from('transactions')
            .update(
              updatePayload(TransactionModel.fromEntity(transaction).toJson()),
            )
            .eq('id', transaction.id);
      });

  Future<void> deleteTransaction(String transactionId) =>
      guardSupabase(() async {
        await _supabaseClient
            .from('transactions')
            .update(tombstone())
            .eq('id', transactionId);
      });
}
