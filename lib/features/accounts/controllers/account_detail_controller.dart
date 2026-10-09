import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/account_transaction_summary.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/account_balance_calculator.dart';
import 'package:get/get.dart';

/// One account with its balance, income/expense totals and recent activity.
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

  static const int recentCount = 10;

  final Rxn<Account> account = Rxn<Account>();
  final Rxn<AccountTransactionSummary> summary =
      Rxn<AccountTransactionSummary>();
  final RxList<Transaction> recent = <Transaction>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();

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
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final (Account loaded, List<Transaction> transactions) = await wait2(
        _accountRepository.getAccountById(accountId),
        _transactionRepository.getAllTransactions(accountId: accountId),
      );
      account.value = loaded.deletedAt == null ? loaded : null;
      summary.value = AccountTransactionSummary(
        balance: AccountBalanceCalculator.calculateBalance(
          loaded.openingBalance,
          transactions,
        ),
        totalIncome: AccountBalanceCalculator.sumIncome(transactions),
        totalExpense: AccountBalanceCalculator.sumExpense(transactions),
        transactionCount: transactions.length,
      );
      recent.assignAll(transactions.take(recentCount));
    } on AppException catch (failure) {
      if (!silent) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }
}
