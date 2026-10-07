import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionRepository {
  TransactionRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  Future<List<Transaction>> getTransactions({
    String? accountId,
    String? categoryId,
    String? contactId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) async {
    return guardSupabase(() async {
      var query = _supabaseClient.from('transactions').select();

      if (accountId != null) {
        query = query.eq('account_id', accountId);
      }
      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }
      if (contactId != null) {
        query = query.eq('contact_id', contactId);
      }
      if (startDate != null) {
        query = query.gte('transaction_date', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('transaction_date', endDate.toIso8601String());
      }

      final response = await query
          .order('transaction_date', ascending: false)
          .range(offset, offset + limit - 1);

      final List<dynamic> raw = response as List<dynamic>;
      final List<Map<String, dynamic>> data =
          raw.map((e) => e as Map<String, dynamic>).toList();
      return data
          .map((json) => TransactionModel.fromJson(json).toEntity())
          .toList();
    });
  }

  Future<Transaction> getTransactionById(String transactionId) async {
    return guardSupabase(() async {
      final response = await _supabaseClient
          .from('transactions')
          .select()
          .eq('id', transactionId)
          .single();

      return TransactionModel.fromJson(response).toEntity();
    });
  }

  Future<void> createTransaction(Transaction transaction) async {
    return guardSupabase(() async {
      await _supabaseClient
          .from('transactions')
          .insert(TransactionModel.fromEntity(transaction).toJson());
    });
  }

  Future<void> updateTransaction(Transaction transaction) async {
    return guardSupabase(() async {
      await _supabaseClient
          .from('transactions')
          .update(TransactionModel.fromEntity(transaction).toJson())
          .eq('id', transaction.id);
    });
  }

  Future<void> deleteTransaction(String transactionId) async {
    return guardSupabase(() async {
      await _supabaseClient
          .from('transactions')
          .delete()
          .eq('id', transactionId);
    });
  }
}