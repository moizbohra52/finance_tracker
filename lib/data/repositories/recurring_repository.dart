import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/models/recurring_transaction.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecurringRepository {
  RecurringRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  Future<List<RecurringTransaction>> getAll() => guardSupabase(() async {
    final List<Map<String, dynamic>> data = await _supabaseClient
        .from('recurring_transactions')
        .select()
        .isFilter('deleted_at', null)
        .order('next_run_at');
    return data.map(RecurringTransactionModel.fromJson).toList();
  });

  /// Upserts on the client-generated id, so a retried create never duplicates.
  Future<void> create(RecurringTransaction rule) => guardSupabase(() async {
    await _supabaseClient
        .from('recurring_transactions')
        .upsert(
          insertPayload(
            _supabaseClient,
            RecurringTransactionModel.toJson(rule),
          ),
        );
  });

  Future<void> update(RecurringTransaction rule) => guardSupabase(() async {
    await _supabaseClient
        .from('recurring_transactions')
        .update(updatePayload(RecurringTransactionModel.toJson(rule)))
        .eq('id', rule.id);
  });

  Future<void> delete(String id) => guardSupabase(() async {
    await _supabaseClient
        .from('recurring_transactions')
        .update(tombstone())
        .eq('id', id);
  });
}
