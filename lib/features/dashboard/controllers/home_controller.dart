import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/report_calculator.dart';
import 'package:finance_tracker/domain/services/report_period.dart';
import 'package:get/get.dart';

/// Presentation state for the home dashboard and the reports tab. All totals
/// come from [FinanceSummaryCalculator]; this class only loads and holds them.
class HomeController extends GetxController {
  HomeController(
    this._accountRepository,
    this._transactionRepository,
    this._contactRepository,
    this._categoryRepository,
    this._notifier,
  );

  final AccountRepository _accountRepository;
  final TransactionRepository _transactionRepository;
  final ContactRepository _contactRepository;
  final CategoryRepository _categoryRepository;
  final DataChangeNotifier _notifier;

  static const int _recentCount = 5;

  /// True only until the first load finishes; refreshes keep showing data.
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final RxBool balanceHidden = false.obs;

  final RxList<Account> accounts = <Account>[].obs;
  final RxMap<String, Decimal> balances = <String, Decimal>{}.obs;
  final RxList<Transaction> recent = <Transaction>[].obs;
  final Rx<Decimal> currentBalance = Decimal.zero.obs;
  final Rx<Decimal> openingBalance = Decimal.zero.obs;
  final Rx<PeriodSummary> today = PeriodSummary.zero.obs;
  final Rx<PeriodSummary> month = PeriodSummary.zero.obs;
  final Rx<KhataSummary> khata = KhataSummary.zero.obs;
  final RxInt contactCount = 0.obs;

  /// This month's expense by category, largest first.
  final RxList<CategoryTotal> monthCategories = <CategoryTotal>[].obs;

  List<Category> _categories = <Category>[];
  bool _hasLoaded = false;

  @override
  void onInit() {
    super.onInit();
    load();
    ever<int>(_notifier.version, (_) => load());
  }

  Category? categoryOf(String? id) {
    if (id == null) return null;
    for (final Category c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String accountName(String id) {
    for (final Account a in accounts) {
      if (a.id == id) return a.name;
    }
    return 'Account';
  }

  Future<void> load() async {
    if (!_hasLoaded) isLoading.value = true;
    error.value = null;
    try {
      final (
        List<Account> loadedAccounts,
        List<Transaction> transactions,
        List<Contact> contacts,
        List<ContactTransaction> contactTransactions,
        List<Category> categories,
      ) = await wait5(
        _accountRepository.getAccounts(),
        _transactionRepository.getAllTransactions(),
        _contactRepository.getContacts(),
        _contactRepository.getAllContactTransactions(),
        _categoryRepository.getCategories(),
      );

      final List<Account> active = loadedAccounts
          .where((Account a) => a.isActive)
          .toList();
      final Map<String, Decimal> byAccount =
          FinanceSummaryCalculator.accountBalances(active, transactions);
      final DateTime now = DateTime.now();
      final DateTime startOfDay = DateTime(now.year, now.month, now.day);

      _categories = categories;
      accounts.assignAll(active);
      balances.assignAll(byAccount);
      recent.assignAll(transactions.take(_recentCount));
      currentBalance.value = FinanceSummaryCalculator.sum(byAccount.values);
      openingBalance.value = FinanceSummaryCalculator.sum(
        active.map((Account a) => a.openingBalance),
      );
      today.value = FinanceSummaryCalculator.period(
        transactions,
        startOfDay,
        startOfDay.add(const Duration(days: 1)),
      );
      month.value = FinanceSummaryCalculator.period(
        transactions,
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
      );
      monthCategories.assignAll(
        ReportCalculator.categoryTotals(
          transactions,
          ReportPeriod.resolve(DatePreset.thisMonth, now),
          TransactionType.expense,
        ),
      );
      khata.value = FinanceSummaryCalculator.khata(
        contacts,
        contactTransactions,
      );
      contactCount.value = contacts.length;
      _hasLoaded = true;
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  void toggleBalanceHidden() => balanceHidden.toggle();
}
