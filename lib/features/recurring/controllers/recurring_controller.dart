import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/recurring_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/recurring_scheduler.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// Recurring rules: list, create, edit, pause/resume, delete, and turning due
/// occurrences into transactions.
class RecurringController extends GetxController {
  RecurringController(
    this._recurringRepository,
    this._transactionRepository,
    this._accountRepository,
    this._categoryRepository,
    this._notifications,
    this._notifier,
  );

  final RecurringRepository _recurringRepository;
  final TransactionRepository _transactionRepository;
  final AccountRepository _accountRepository;
  final CategoryRepository _categoryRepository;
  final NotificationCoordinator _notifications;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final RxList<RecurringTransaction> rules = <RecurringTransaction>[].obs;
  final RxList<Account> accounts = <Account>[].obs;
  final RxList<Category> categories = <Category>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final RxBool lookupsLoaded = false.obs;
  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();
  final SubmitState toggle = SubmitState();

  bool _running = false;

  @override
  void onInit() {
    super.onInit();
    // Materialise anything that came due while the app was closed, then show
    // the list.
    runDue().then((_) => load());
    ever<int>(_notifier.version, (_) => load(silent: true));
  }

  Category? categoryOf(String? id) {
    if (id == null) return null;
    for (final Category c in categories) {
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

  List<Category> categoriesFor(TransactionType type) => categories
      .where(
        (Category c) =>
            c.type == CategoryType.both ||
            (type == TransactionType.income
                ? c.type == CategoryType.income
                : c.type == CategoryType.expense),
      )
      .toList();

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final (
        List<RecurringTransaction> loaded,
        List<Account> loadedAccounts,
      ) = await wait2(
        _recurringRepository.getAll(),
        _accountRepository.getAccounts(),
      );
      rules.assignAll(loaded);
      accounts.assignAll(loadedAccounts.where((Account a) => a.isActive));
      categories.assignAll(await _categoryRepository.getCategories());
    } on AppException catch (failure) {
      if (!silent || rules.isEmpty) error.value = failure.message;
    } finally {
      isLoading.value = false;
      lookupsLoaded.value = true;
    }
  }

  /// Creates a transaction for every occurrence that is due and moves each
  /// rule to its next occurrence.
  ///
  /// Safe to run any number of times, on any device: each occurrence has a
  /// deterministic transaction id and is inserted only if absent, and a rule
  /// only advances after its transactions were written.
  Future<int> runDue() async {
    if (_running) return 0;
    _running = true;
    int created = 0;
    try {
      final (
        List<RecurringTransaction> all,
        List<Account> allAccounts,
      ) = await wait2(
        _recurringRepository.getAll(),
        _accountRepository.getAccounts(),
      );
      final Set<String> usable = <String>{
        for (final Account a in allAccounts)
          if (a.isActive) a.id,
      };
      final DateTime now = DateTime.now();
      for (final RecurringTransaction rule in all) {
        final List<DateTime> due = RecurringScheduler.due(rule, now);
        if (due.isEmpty || !usable.contains(rule.accountId)) continue;
        try {
          for (final DateTime occurrence in due) {
            await _transactionRepository.createTransaction(
              Transaction(
                id: RecurringScheduler.transactionId(rule.id, occurrence),
                userId: '',
                accountId: rule.accountId,
                categoryId: rule.categoryId,
                type: rule.type,
                amount: rule.amount,
                transactionDate: occurrence,
                note: rule.note,
                description: 'Recurring',
                createdAt: now,
                updatedAt: now,
              ),
              onlyIfAbsent: true,
            );
            created++;
          }
          final DateTime? next = RecurringScheduler.nextAfter(rule, due.last);
          await _recurringRepository.update(
            rule.copyWith(nextRunAt: next ?? due.last, active: next != null),
          );
          await _announce(rule, due);
        } on AppException catch (failure) {
          // Leave this rule where it was; it retries on the next run.
          error.value = failure.message;
        }
      }
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      _running = false;
    }
    if (created > 0) _notifier.markChanged();
    return created;
  }

  /// Tells the user a run was recorded. Best effort: the transactions are
  /// what matters, so a failure here never fails the run.
  Future<void> _announce(RecurringTransaction rule, List<DateTime> due) async {
    final String label = (rule.note ?? '').isNotEmpty
        ? rule.note!
        : 'Recurring transaction';
    try {
      await _notifications.raise(
        id: RecurringScheduler.notificationId(rule.id, due.last),
        type: NotificationType.recurring,
        title: '$label recorded',
        body: due.length == 1
            ? '${AppFormatters.money(rule.amount)} was added automatically.'
            : '${due.length} transactions were added automatically.',
        referenceId: rule.id,
      );
    } on AppException catch (failure) {
      developer.log(
        'Recurring notification not raised: ${failure.runtimeType}',
        name: 'recurring',
      );
    }
  }

  /// [id] is generated once per form so a retried save upserts one row.
  Future<bool> saveRule({
    required String id,
    RecurringTransaction? existing,
    required String accountId,
    required String? categoryId,
    required TransactionType type,
    required Decimal amount,
    required RecurringFrequency frequency,
    required int intervalCount,
    required DateTime startDate,
    required DateTime? endDate,
    required String? note,
  }) => save.run(() async {
    final DateTime now = DateTime.now();
    RecurringTransaction rule = RecurringTransaction(
      id: id,
      userId: existing?.userId ?? '',
      accountId: accountId,
      categoryId: categoryId,
      type: type,
      amount: amount,
      frequency: frequency,
      intervalCount: intervalCount,
      startDate: startDate,
      endDate: endDate,
      nextRunAt: startDate,
      active: existing?.active ?? true,
      note: note,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final bool scheduleChanged =
        existing == null ||
        existing.startDate != startDate ||
        existing.endDate != endDate ||
        existing.frequency != frequency ||
        existing.intervalCount != intervalCount;
    if (!scheduleChanged) {
      rule = rule.copyWith(nextRunAt: existing.nextRunAt);
    } else {
      // A new or changed schedule starts from now: nothing in the past is
      // back-filled.
      final DateTime? first = RecurringScheduler.firstOnOrAfter(
        rule,
        existing == null ? startDate : now,
      );
      rule = rule.copyWith(
        nextRunAt: first ?? existing?.nextRunAt ?? startDate,
        active: first != null && (existing?.active ?? true),
      );
    }
    if (existing == null) {
      await _recurringRepository.create(rule);
    } else {
      await _recurringRepository.update(rule);
    }
    _notifier.markChanged();
  });

  /// Pauses or resumes. Resuming skips whatever was missed while paused.
  Future<bool> setActive(RecurringTransaction rule, bool active) =>
      toggle.run(() async {
        RecurringTransaction updated = rule.copyWith(active: active);
        if (active) {
          final DateTime? next = RecurringScheduler.firstOnOrAfter(
            rule,
            DateTime.now(),
          );
          // An ended rule cannot be resumed.
          if (next == null) return;
          updated = updated.copyWith(nextRunAt: next);
        }
        await _recurringRepository.update(updated);
        _notifier.markChanged();
      });

  Future<bool> deleteRule(String id) => deletion.run(() async {
    await _recurringRepository.delete(id);
    _notifier.markChanged();
  });

  static String newId() => _uuid.v4();
}
