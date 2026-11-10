import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/account_transaction_summary.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/entities/transaction_summary.dart';
import 'package:finance_tracker/domain/services/account_balance_calculator.dart';
import 'package:get/get.dart';

/// One account with its balance, income/expense totals and every
/// transaction, loaded a page at a time.
class AccountDetailController extends GetxController {
  AccountDetailController(
    this._accountRepository,
    this._transactionRepository,
    this._notifier,
    this.accountId,
  );

  final AccountRepository _accountRepository;
  final TransactionRepository _transactionRepository;
  final DataChangeNotifier _notifier;
  final String accountId;

  static const int pageSize = 30;

  final Rxn<Account> account = Rxn<Account>();
  final Rxn<AccountTransactionSummary> summary =
      Rxn<AccountTransactionSummary>();
  final RxList<Transaction> items = <Transaction>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxnString error = RxnString();

  int _generation = 0;

  // GetX does not dispose workers, and the notifier outlives this
  // controller, so without this a closed controller keeps reloading.
  late final Worker _changes;

  @override
  void onClose() {
    _changes.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    load();
    _changes = ever<int>(_notifier.version, (_) => load(silent: true));
  }

  Future<void> load({bool silent = false}) async {
    final int generation = ++_generation;
    if (!silent) isLoading.value = true;
    error.value = null;
    // A silent reload refetches every row already on screen, so the list
    // does not jump back to the first page after an edit.
    final int limit = silent && items.length > pageSize
        ? items.length
        : pageSize;
    try {
      final (
        Account loaded,
        TransactionSummary totals,
        TransactionSummary opening,
        List<Transaction> page,
      ) = await wait4(
        _accountRepository.getAccountById(accountId),
        _transactionRepository.getTransactionSummary(accountId: accountId),
        // Opening-balance rows are already in the account's opening
        // balance (see AccountBalanceCalculator), so they leave the inflow.
        _transactionRepository.getTransactionSummary(
          accountId: accountId,
          type: TransactionType.opening_balance,
        ),
        _transactionRepository.getTransactions(
          accountId: accountId,
          limit: limit,
        ),
      );
      if (generation != _generation) return;
      final Decimal inflow = totals.totalInflow - opening.totalInflow;
      account.value = loaded.deletedAt == null ? loaded : null;
      summary.value = AccountTransactionSummary(
        balance: AccountBalanceCalculator.balanceFromTotals(
          loaded.openingBalance,
          inflow,
          totals.totalOutflow,
        ),
        totalIncome: inflow,
        totalExpense: totals.totalOutflow,
        transactionCount: totals.totalCount,
      );
      items.assignAll(page);
      hasMore.value = page.length == limit;
    } on AppException catch (failure) {
      if (!silent && generation == _generation) error.value = failure.message;
    } finally {
      if (generation == _generation) isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoading.value || isLoadingMore.value || !hasMore.value) return;
    final int generation = _generation;
    isLoadingMore.value = true;
    try {
      final List<Transaction> page = await _transactionRepository
          .getTransactions(
            accountId: accountId,
            limit: pageSize,
            offset: items.length,
          );
      if (generation != _generation) return;
      items.addAll(page);
      hasMore.value = page.length == pageSize;
    } on AppException {
      // The rows already shown stay; scrolling again retries.
    } finally {
      isLoadingMore.value = false;
    }
  }
}
