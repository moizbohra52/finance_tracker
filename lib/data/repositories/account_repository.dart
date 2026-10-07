import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountRepository {
  AccountRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  Future<List<Account>> getAccounts() => guardSupabase(() async {
    final List<Map<String, dynamic>> data = await _supabaseClient
        .from('accounts')
        .select()
        .isFilter('deleted_at', null)
        .order('created_at');
    return data
        .map(
          (Map<String, dynamic> json) => AccountModel.fromJson(json).toEntity(),
        )
        .toList();
  });

  Future<Account> getAccountById(String accountId) => guardSupabase(() async {
    final Map<String, dynamic> response = await _supabaseClient
        .from('accounts')
        .select()
        .eq('id', accountId)
        .single();
    return AccountModel.fromJson(response).toEntity();
  });

  /// Upserts on the client-generated id, so a retried create never duplicates.
  Future<void> createAccount(Account account) => guardSupabase(() async {
    await _supabaseClient
        .from('accounts')
        .upsert(
          insertPayload(
            _supabaseClient,
            AccountModel.fromEntity(account).toJson(),
          ),
        );
  });

  Future<void> updateAccount(Account account) => guardSupabase(() async {
    await _supabaseClient
        .from('accounts')
        .update(updatePayload(AccountModel.fromEntity(account).toJson()))
        .eq('id', account.id);
  });

  /// Soft delete: transactions reference accounts, so history must survive.
  Future<void> deleteAccount(String accountId) => guardSupabase(() async {
    await _supabaseClient
        .from('accounts')
        .update(tombstone())
        .eq('id', accountId);
  });
}
