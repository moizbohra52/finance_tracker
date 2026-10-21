import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/report_calculator.dart';
import 'package:finance_tracker/domain/services/report_period.dart';
import 'package:get/get.dart';

/// One month as a calendar: income and expense per day, the month's totals,
/// and the transactions of the chosen day. Totals come from ReportCalculator,
/// so they match the reports screen.
class CalendarController extends GetxController {
  CalendarController(
    this._transactionRepository,
    this._accountRepository,
    this._categoryRepository,
    this._notifier,
  );

  final TransactionRepository _transactionRepository;
  final AccountRepository _accountRepository;
  final CategoryRepository _categoryRepository;
  final DataChangeNotifier _notifier;

  /// First instant of the shown month.
  final Rx<DateTime> month = _monthOf(DateTime.now()).obs;
  final Rx<DateTime> selectedDay = _dayOf(DateTime.now()).obs;

  /// One point per day of [month], the 1st first.
  final RxList<TrendPoint> days = <TrendPoint>[].obs;
  final Rx<PeriodSummary> summary = PeriodSummary.zero.obs;
  final RxList<Transaction> dayItems = <Transaction>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();

  /// Every transaction of [month], newest first.
  List<Transaction> items = <Transaction>[];
  List<Category> _categories = <Category>[];
  List<Account> _accounts = <Account>[];

  // GetX does not dispose workers, and the notifier outlives this
  // controller, so without this a closed controller keeps reloading.
  late final Worker _changes;

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);
  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Empty cells before the 1st of [month] in a week that starts on
  /// [firstWeekday] (a DateTime.monday..sunday value).
  static int leadingBlanks(DateTime month, int firstWeekday) =>
      (DateTime(month.year, month.month).weekday - firstWeekday + 7) % 7;

  @override
  void onInit() {
    super.onInit();
    load();
    _changes = ever<int>(_notifier.version, (_) => load(silent: true));
  }

  @override
  void onClose() {
    _changes.dispose();
    super.onClose();
  }

  Category? categoryOf(String? id) =>
      _categories.firstWhereOrNull((Category c) => c.id == id);

  String accountName(String id) =>
      _accounts.firstWhereOrNull((Account a) => a.id == id)?.name ?? 'Account';

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    final DateTime start = month.value;
    final ReportPeriod period = ReportPeriod(
      preset: DatePreset.custom,
      start: start,
      end: DateTime(start.year, start.month + 1),
    );
    try {
      final (
        List<Transaction> loaded,
        List<Account> accounts,
        List<Category> categories,
      ) = await wait3(
        _transactionRepository.getAllTransactions(
          start: period.start,
          end: period.end,
        ),
        _accountRepository.getAccounts(),
        _categoryRepository.getCategories(),
      );
      // A month switch while loading: the newer load owns the screen.
      if (month.value != start) return;
      items = loaded;
      _accounts = accounts;
      _categories = categories;
      days.assignAll(ReportCalculator.trend(loaded, period));
      summary.value = ReportCalculator.summary(loaded, period);
      _showDay();
    } on AppException catch (failure) {
      if (!silent) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  void selectDay(DateTime day) {
    selectedDay.value = _dayOf(day);
    _showDay();
  }

  Future<void> previousMonth() => _goTo(-1);

  Future<void> nextMonth() => _goTo(1);

  /// The current month opens on today, any other on its 1st.
  Future<void> _goTo(int offset) {
    final DateTime next = DateTime(
      month.value.year,
      month.value.month + offset,
    );
    final DateTime now = DateTime.now();
    month.value = next;
    selectedDay.value = next == _monthOf(now) ? _dayOf(now) : next;
    return load();
  }

  void _showDay() {
    dayItems.assignAll(
      items.where(
        (Transaction t) => _dayOf(t.transactionDate) == selectedDay.value,
      ),
    );
  }
}
