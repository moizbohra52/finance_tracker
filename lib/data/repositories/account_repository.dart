import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountRepository {
  AccountRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  Future<List<Account>> getAccounts() => guardSupabase(() async {
    final response = await _supabaseClient
        .from('accounts')
        .select();
    final List<dynamic> raw = response as List<dynamic>;
    final List<Map<String, dynamic>> data =
        raw.map((e) => e as Map<String, dynamic>).toList();
    return data
        .map((json) => AccountModel.fromJson(json).toEntity())
        .toList();
  });

  Future<Account> getAccountById(String accountId) => guardSupabase(() async {
    final response = await _supabaseClient
        .from('accounts')
        .select()
        .eq('id', accountId)
        .single();
    return AccountModel.fromJson(response).toEntity();
  });

  Future<void> createAccount(Account account) => guardSupabase(() async {
    await _supabaseClient
        .from('accounts')
        .insert(AccountModel.fromEntity(account).toJson());
  });

  Future<void> updateAccount(Account account) => guardSupabase(() async {
    await _supabaseClient
        .from('accounts')
        .update(AccountModel.fromEntity(account).toJson())
        .eq('id', account.id);
  });

  Future<void> deleteAccount(String accountId) => guardSupabase(() async {
    await _supabaseClient
        .from('accounts')
        .delete()
        .eq('id', accountId);
  });
}