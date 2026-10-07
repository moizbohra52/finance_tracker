import 'package:decimal/decimal.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/account_transaction_summary.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/account_balance_calculator.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AccountController extends GetxController {
  AccountController(this._accountRepository);

  final AccountRepository _accountRepository;

  final RxList<Account> accounts = RxList<Account>();
  final RxBool isLoading = RxBool(false);
  final RxString error = RxString('');

  final SupabaseClient _supabaseClient = Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  @override
  void onInit() {
    super.onInit();
    loadAccounts();
  }

  Future<void> loadAccounts() async {
    try {
      isLoading.value = true;
      error.value = '';
      final List<Account> data = await _accountRepository.getAccounts();
      accounts.assignAll(data);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> addAccount({
    required String name,
    required AccountType type,
    required Decimal openingBalance,
    DateTime? openingBalanceDate,
  }) async {
    final String userId = _supabaseClient.auth.currentUser?.id ?? '';
    if (userId.isEmpty) {
      throw Exception('User not authenticated');
    }
    final Account account = Account(
      id: _uuid.v4(),
      userId: userId,
      name: name,
      type: type,
      openingBalance: openingBalance,
      openingBalanceDate: openingBalanceDate,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    try {
      isLoading.value = true;
      error.value = '';
      await _accountRepository.createAccount(account);
      accounts.add(account);
    } catch (e) {
      error.value = e.toString();
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> updateAccount(Account account) async {
    try {
      isLoading.value = true;
      error.value = '';
      await _accountRepository.updateAccount(account);
      final int index = accounts.indexWhere((a) => a.id == account.id);
      if (index != -1) {
        accounts[index] = account;
      }
    } catch (e) {
      error.value = e.toString();
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> deleteAccount(String accountId) async {
    try {
      isLoading.value = true;
      error.value = '';
      await _accountRepository.deleteAccount(accountId);
      accounts.removeWhere((a) => a.id == accountId);
    } catch (e) {
      error.value = e.toString();
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  List<Account> get activeAccounts =>
      accounts.where((a) => a.isActive).toList();

  Account? get defaultAccount {
    final List<Account> active = activeAccounts;
    if (active.isEmpty) return null;
    // Prefer a cash account as the default; otherwise the first active account.
    final cash = active.firstWhereOrNull((a) => a.type == AccountType.cash);
    return cash ?? active.first;
  }

  /// Fetches transactions for the given account from Supabase and calculates
  /// the current balance using the centralized [AccountBalanceCalculator].
  Future<Decimal> getAccountBalance(Account account) async {
    final List<Map<String, dynamic>> data = await _supabaseClient
        .from('transactions')
        .select()
        .eq('account_id', account.id)
        .isFilter('deleted_at', null);

    final List<Transaction> transactions =
        data.map((json) => Transaction.fromJson(json)).toList();

    return AccountBalanceCalculator.calculateBalance(
      account.openingBalance,
      transactions,
    );
  }

  /// Transaction summary for the account detail view.
  Future<AccountTransactionSummary> getAccountTransactionSummary(
    Account account,
  ) async {
    final List<Map<String, dynamic>> data = await _supabaseClient
        .from('transactions')
        .select()
        .eq('account_id', account.id)
        .isFilter('deleted_at', null);

    final List<Transaction> transactions =
        data.map((json) => Transaction.fromJson(json)).toList();

    final Decimal balance =
        AccountBalanceCalculator.calculateBalance(account.openingBalance, transactions);
    final Decimal income = AccountBalanceCalculator.sumIncome(transactions);
    final Decimal expense = AccountBalanceCalculator.sumExpense(transactions);

    return AccountTransactionSummary(
      balance: balance,
      totalIncome: income,
      totalExpense: expense,
      transactionCount: transactions.length,
    );
  }
}