import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AccountDatasource {
  Future<List<Account>> getAccounts();
  Future<Account> getAccountById(String accountId);
  Future<void> createAccount(Account account);
  Future<void> updateAccount(Account account);
  Future<void> deleteAccount(String accountId);
}

class AccountDatasourceImpl implements AccountDatasource {
  AccountDatasourceImpl(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  @override
  Future<List<Account>> getAccounts() async {
    final raw = await _supabaseClient.from('accounts').select();
    final List<dynamic> list = raw as List<dynamic>;
    final List<Map<String, dynamic>> data =
        list.map((e) => e as Map<String, dynamic>).toList();
    return data
        .map((json) => AccountModel.fromJson(json).toEntity())
        .toList();
  }

  @override
  Future<Account> getAccountById(String accountId) async {
    final response = await _supabaseClient
        .from('accounts')
        .select('*')
        .eq('id', accountId)
        .single();
    final Map<String, dynamic> json = response as Map<String, dynamic>;
    return AccountModel.fromJson(json).toEntity();
  }

  @override
  Future<void> createAccount(Account account) async {
    final response = await _supabaseClient
        .from('accounts')
        .insert(AccountModel.fromEntity(account).toJson());
  }

  @override
  Future<void> updateAccount(Account account) async {
    await _supabaseClient
        .from('accounts')
        .update(AccountModel.fromEntity(account).toJson())
        .eq('id', account.id);
  }

  @override
  Future<void> deleteAccount(String accountId) async {
    await _supabaseClient
        .from('accounts')
        .delete()
        .eq('id', accountId);
  }
}