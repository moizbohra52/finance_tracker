import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/models/budget.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BudgetRepository {
  BudgetRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  Future<List<Budget>> getBudgets() => guardSupabase(() async {
    final List<Map<String, dynamic>> data = await _supabaseClient
        .from('budgets')
        .select()
        .isFilter('deleted_at', null)
        .order('created_at');
    return data.map(BudgetModel.fromJson).toList();
  });

  /// Upserts on the client-generated id, so a retried create never duplicates.
  Future<void> createBudget(Budget budget) => guardSupabase(() async {
    await _supabaseClient
        .from('budgets')
        .upsert(insertPayload(_supabaseClient, BudgetModel.toJson(budget)));
  });

  Future<void> updateBudget(Budget budget) => guardSupabase(() async {
    await _supabaseClient
        .from('budgets')
        .update(updatePayload(BudgetModel.toJson(budget)))
        .eq('id', budget.id);
  });

  Future<void> deleteBudget(String budgetId) => guardSupabase(() async {
    await _supabaseClient
        .from('budgets')
        .update(tombstone())
        .eq('id', budgetId);
  });
}
