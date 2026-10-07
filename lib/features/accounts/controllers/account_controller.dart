import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// Account list plus create, edit (including the opening balance) and delete.
class AccountController extends GetxController {
  AccountController(
    this._accountRepository,
    this._transactionRepository,
    this._notifier,
  );

  final AccountRepository _accountRepository;
  final TransactionRepository _transactionRepository;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final RxList<Account> accounts = <Account>[].obs;
  final RxMap<String, Decimal> balances = <String, Decimal>{}.obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();

  @override
  void onInit() {
    super.onInit();
    load();
    ever<int>(_notifier.version, (_) => load(silent: true));
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final (
        List<Account> loaded,
        List<Transaction> transactions,
      ) = await wait2(
        _accountRepository.getAccounts(),
        _transactionRepository.getAllTransactions(),
      );
      accounts.assignAll(loaded);
      balances.assignAll(
        FinanceSummaryCalculator.accountBalances(loaded, transactions),
      );
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// [id] is generated once per form so a retried save upserts one row.
  Future<bool> saveAccount({
    required String id,
    Account? existing,
    required String name,
    required AccountType type,
    required Decimal openingBalance,
    required DateTime openingBalanceDate,
  }) => save.run(() async {
    final DateTime now = DateTime.now();
    final Account account = Account(
      id: id,
      userId: existing?.userId ?? '',
      name: name,
      type: type,
      openingBalance: openingBalance,
      openingBalanceDate: openingBalanceDate,
      isActive: existing?.isActive ?? true,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (existing == null) {
      await _accountRepository.createAccount(account);
    } else {
      await _accountRepository.updateAccount(account);
    }
    _notifier.markChanged();
  });

  Future<bool> deleteAccount(String accountId) => deletion.run(() async {
    await _accountRepository.deleteAccount(accountId);
    _notifier.markChanged();
  });

  static String newId() => _uuid.v4();
}
