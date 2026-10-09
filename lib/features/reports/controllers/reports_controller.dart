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

/// Loads the transactions needed for a report period and exposes the
/// calculated figures. Changing the period re-computes from data already in
/// memory when it is covered, and only refetches when it is not.
class ReportsController extends GetxController {
  ReportsController(
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

  static const int comparisonMonths = 6;

  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();

  final Rx<ReportPeriod> period = ReportPeriod.resolve(
    DatePreset.thisMonth,
    DateTime.now(),
  ).obs;

  /// Which side the category breakdown shows.
  final Rx<TransactionType> categoryType = TransactionType.expense.obs;

  final Rx<PeriodSummary> summary = PeriodSummary.zero.obs;
  final Rx<KhataSummary> khata = KhataSummary.zero.obs;
  final RxList<CategoryTotal> categoryTotals = <CategoryTotal>[].obs;
  final RxList<AccountTotal> accountTotals = <AccountTotal>[].obs;
  final RxList<TrendPoint> trend = <TrendPoint>[].obs;
  final RxList<TrendPoint> monthly = <TrendPoint>[].obs;
  final RxInt transactionCount = 0.obs;

  List<Transaction> _transactions = <Transaction>[];
  List<Category> _categories = <Category>[];
  List<Account> _accounts = <Account>[];
  DateTime? _fetchedStart;
  DateTime? _fetchedEnd;

  bool get hasData => transactionCount.value > 0;
  TrendBucket get bucket => ReportCalculator.bucketFor(period.value);

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
    _changes = ever<int>(_notifier.version, (_) => load(force: true));
  }

  Category? categoryOf(String? id) {
    if (id == null) return null;
    for (final Category c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String accountName(String id) {
    for (final Account a in _accounts) {
      if (a.id == id) return a.name;
    }
    return 'Account';
  }

  /// The earliest/latest instants that must be loaded for [p] plus the
  /// monthly comparison window.
  (DateTime, DateTime) _window(ReportPeriod p) {
    final DateTime now = DateTime.now();
    final DateTime comparisonStart = DateTime(
      now.year,
      now.month - (comparisonMonths - 1),
    );
    final DateTime comparisonEnd = DateTime(now.year, now.month + 1);
    return (
      p.start.isBefore(comparisonStart) ? p.start : comparisonStart,
      p.end.isAfter(comparisonEnd) ? p.end : comparisonEnd,
    );
  }

  Future<void> load({bool force = false}) async {
    final ReportPeriod p = period.value;
    final (DateTime start, DateTime end) = _window(p);
    final bool covered =
        !force &&
        _fetchedStart != null &&
        !start.isBefore(_fetchedStart!) &&
        !end.isAfter(_fetchedEnd!);
    if (covered) {
      _recompute();
      return;
    }
    if (_fetchedStart == null || force) isLoading.value = true;
    error.value = null;
    try {
      final (
        List<Transaction> transactions,
        List<Account> accounts,
        List<Category> categories,
        List<Contact> contacts,
        List<ContactTransaction> entries,
      ) = await wait5(
        _transactionRepository.getAllTransactions(start: start, end: end),
        _accountRepository.getAccounts(),
        _categoryRepository.getCategories(),
        _contactRepository.getContacts(),
        _contactRepository.getAllContactTransactions(),
      );
      _transactions = transactions;
      _accounts = accounts;
      _categories = categories;
      _fetchedStart = start;
      _fetchedEnd = end;
      khata.value = FinanceSummaryCalculator.khata(contacts, entries);
      _recompute();
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  void _recompute() {
    final ReportPeriod p = period.value;
    summary.value = ReportCalculator.summary(_transactions, p);
    categoryTotals.assignAll(
      ReportCalculator.categoryTotals(_transactions, p, categoryType.value),
    );
    accountTotals.assignAll(ReportCalculator.accountTotals(_transactions, p));
    trend.assignAll(ReportCalculator.trend(_transactions, p));
    monthly.assignAll(
      ReportCalculator.monthlyComparison(
        _transactions,
        DateTime.now(),
        months: comparisonMonths,
      ),
    );
    transactionCount.value = _transactions
        .where(
          (Transaction t) =>
              p.contains(t.transactionDate) &&
              (t.type == TransactionType.income ||
                  t.type == TransactionType.expense),
        )
        .length;
  }

  void selectPreset(DatePreset preset) {
    if (preset == DatePreset.custom) return;
    period.value = ReportPeriod.resolve(preset, DateTime.now());
    load();
  }

  /// [start] and [end] are inclusive calendar days.
  void selectCustom(DateTime start, DateTime end) {
    period.value = ReportPeriod.resolve(
      DatePreset.custom,
      DateTime.now(),
      customStart: start,
      customEnd: end,
    );
    load();
  }

  void selectCategoryType(TransactionType type) {
    categoryType.value = type;
    _recompute();
  }
}
