import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/budget_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/budget_calculator.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// Budget list with live progress, plus create, edit and delete. Every
/// reload also raises any newly crossed 75/90/100% alert exactly once.
class BudgetController extends GetxController {
  BudgetController(
    this._budgetRepository,
    this._transactionRepository,
    this._categoryRepository,
    this._notifications,
    this._notifier,
  );

  final BudgetRepository _budgetRepository;
  final TransactionRepository _transactionRepository;
  final CategoryRepository _categoryRepository;
  final NotificationCoordinator _notifications;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final RxList<BudgetStatus> statuses = <BudgetStatus>[].obs;
  final RxList<Category> categories = <Category>[].obs;

  /// Every stored category row, so budget rows keep their label after a
  /// category is switched off, deleted, or tombstoned by sync. [categories]
  /// stays active-only for the form's picker.
  final RxList<Category> categoryIndex = <Category>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();

  /// Alert ids already sent this session, so a reload does not resend them.
  /// The ids are deterministic, so the server also ignores true duplicates.
  final Set<String> _raised = <String>{};

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

  Category? categoryOf(String? id) {
    if (id == null) return null;
    for (final Category c in categoryIndex) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// "All expenses" or the category name.
  String nameOf(Budget b) => b.categoryId == null
      ? 'All expenses'.tr
      : categoryOf(b.categoryId)?.name ?? 'Category'.tr;

  List<Category> get expenseCategories => categories
      .where(
        (Category c) =>
            c.type == CategoryType.expense || c.type == CategoryType.both,
      )
      .toList();

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final List<Budget> budgets = await _budgetRepository.getBudgets();
      final (List<Category> active, List<Category> all) = await wait2(
        _categoryRepository.getCategories(),
        _categoryRepository.getAllCategories(),
      );
      final DateTime now = DateTime.now();
      final (DateTime, DateTime)? window = BudgetCalculator.window(
        budgets,
        now,
      );
      final List<Transaction> transactions = window == null
          ? <Transaction>[]
          : await _transactionRepository.getAllTransactions(
              start: window.$1,
              end: window.$2,
            );
      categories.assignAll(active);
      categoryIndex.assignAll(all);
      final List<BudgetStatus> computed = BudgetCalculator.statuses(
        budgets,
        transactions,
        now,
      );
      statuses.assignAll(computed);
      await _raiseAlerts(computed);
    } on AppException catch (failure) {
      if (!silent || statuses.isEmpty) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _raiseAlerts(List<BudgetStatus> computed) async {
    // Off in settings: nothing is raised and nothing is remembered as sent,
    // so turning it back on raises whatever is currently crossed.
    if (!_notifications.preferences.value.allows(
      NotificationType.budgetAlert,
    )) {
      return;
    }
    for (final BudgetStatus status in computed) {
      for (final BudgetAlert alert in BudgetCalculator.alertsFor(status)) {
        if (!_raised.add(alert.id)) continue;
        try {
          await _notifications.raise(
            id: alert.id,
            type: NotificationType.budgetAlert,
            // Stored as written now: the entry keeps this language.
            title: alert.threshold >= 100
                ? '@name budget exceeded'.trParams(<String, String>{
                    'name': nameOf(status.budget),
                  })
                : '@name budget at @percent%'.trParams(<String, String>{
                    'name': nameOf(status.budget),
                    'percent': '${alert.threshold}',
                  }),
            body: 'You have spent @spent of @total.'.trParams(<String, String>{
              'spent': AppFormatters.money(status.spent),
              'total': AppFormatters.money(status.budget.amount),
            }),
            referenceId: alert.budgetId,
          );
        } on AppException {
          // Alerts are best effort: forget it so the next load retries.
          _raised.remove(alert.id);
        }
      }
    }
  }

  /// [id] is generated once per form so a retried save upserts one row.
  Future<bool> saveBudget({
    required String id,
    Budget? existing,
    required String? categoryId,
    required Decimal amount,
    required BudgetPeriodType periodType,
    required DateTime startDate,
    required DateTime? endDate,
    required bool alert75,
    required bool alert90,
    required bool alert100,
  }) => save.run(() async {
    final DateTime now = DateTime.now();
    final Budget budget = Budget(
      id: id,
      userId: existing?.userId ?? '',
      categoryId: categoryId,
      amount: amount,
      periodType: periodType,
      startDate: startDate,
      endDate: periodType == BudgetPeriodType.custom ? endDate : null,
      alert75: alert75,
      alert90: alert90,
      alert100: alert100,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (existing == null) {
      await _budgetRepository.createBudget(budget);
    } else {
      await _budgetRepository.updateBudget(budget);
    }
    _notifier.markChanged();
  });

  Future<bool> deleteBudget(String budgetId) => deletion.run(() async {
    await _budgetRepository.deleteBudget(budgetId);
    _notifier.markChanged();
  });

  static String newId() => _uuid.v4();
}
