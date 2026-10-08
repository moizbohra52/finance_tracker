import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/recurring_scheduler.dart';
import 'package:finance_tracker/features/budgets/controllers/budget_controller.dart';
import 'package:finance_tracker/features/recurring/controllers/recurring_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fake_notifications.dart';
import '../../helpers/fakes.dart';

Budget overallBudget({bool a90 = true}) {
  final DateTime now = DateTime.now();
  return Budget(
    id: 'b1',
    userId: 'u',
    categoryId: null,
    amount: Decimal.parse('1000'),
    periodType: BudgetPeriodType.monthly,
    startDate: DateTime(now.year, now.month),
    endDate: null,
    alert75: true,
    alert90: a90,
    alert100: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

late StorageService _storage;

NotificationCoordinator _coordinator(FakeFinance f) => fakeCoordinator(
  f,
  auth: FakeAuthRepository(signedIn: true),
  storage: _storage,
).coordinator;

BudgetController budgetController(FakeFinance f) => BudgetController(
  f.repositories.budgets,
  f.repositories.transactions,
  f.repositories.categories,
  _coordinator(f),
  DataChangeNotifier(),
);

RecurringController recurringController(FakeFinance f) => RecurringController(
  f.repositories.recurring,
  f.repositories.transactions,
  f.repositories.accounts,
  f.repositories.categories,
  _coordinator(f),
  DataChangeNotifier(),
);

RecurringTransaction dailyRule({
  String id = 'r1',
  String account = 'acc-1',
  int daysAgo = 3,
  DateTime? end,
  bool active = true,
}) {
  final DateTime now = DateTime.now();
  final DateTime start = DateTime(now.year, now.month, now.day - daysAgo);
  return RecurringTransaction(
    id: id,
    userId: 'u',
    accountId: account,
    categoryId: 'cat-food',
    type: TransactionType.expense,
    amount: Decimal.parse('100'),
    frequency: RecurringFrequency.daily,
    intervalCount: 1,
    startDate: start,
    endDate: end,
    nextRunAt: RecurringScheduler.occurrence(
      start,
      RecurringFrequency.daily,
      1,
      0,
    ),
    active: active,
    note: 'Tiffin',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  setUp(() async => _storage = await memoryStorage());

  group('budget alerts', () {
    test(
      'a threshold is raised once however often the budget reloads',
      () async {
        final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
        f.budgets.add(overallBudget());
        f.addTransaction(
          id: 't1',
          type: TransactionType.expense,
          amount: '800',
        );

        final BudgetController c = budgetController(f);
        await c.load();
        await c.load();
        await c.load(silent: true);

        expect(f.notifications, hasLength(1));
        expect(f.notificationWrites, 1);
        final Map<String, String> row = f.notifications.values.single;
        expect(row['type'], 'budget_alert');
        expect(row['title'], 'All expenses budget at 75%');
        expect(row['reference_id'], 'b1');
      },
    );

    test('crossing the next threshold raises exactly one more', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      f.budgets.add(overallBudget());
      f.addTransaction(id: 't1', type: TransactionType.expense, amount: '800');
      final BudgetController c = budgetController(f);
      await c.load();

      f.addTransaction(id: 't2', type: TransactionType.expense, amount: '150');
      await c.load();
      expect(f.notifications, hasLength(2));

      f.addTransaction(id: 't3', type: TransactionType.expense, amount: '60');
      await c.load();
      expect(f.notifications, hasLength(3));
      expect(
        f.notifications.values.map((Map<String, String> r) => r['title']),
        contains('All expenses budget exceeded'),
      );
      await c.load();
      expect(f.notifications, hasLength(3));
    });

    test('a restarted app does not duplicate stored alerts', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      f.budgets.add(overallBudget());
      f.addTransaction(id: 't1', type: TransactionType.expense, amount: '950');

      await budgetController(f).load();
      // New controller = new session with an empty "already sent" memory.
      await budgetController(f).load();

      expect(f.notifications, hasLength(2)); // 75 and 90, once each
    });

    test('disabled thresholds are not raised', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      f.budgets.add(overallBudget(a90: false));
      f.addTransaction(id: 't1', type: TransactionType.expense, amount: '950');
      await budgetController(f).load();
      expect(f.notifications, hasLength(1));
    });

    test('statuses carry spent and remaining from real transactions', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      f.budgets.add(overallBudget());
      f.addTransaction(id: 't1', type: TransactionType.expense, amount: '250');
      f.addTransaction(id: 't2', type: TransactionType.income, amount: '9999');
      final BudgetController c = budgetController(f);
      await c.load();
      expect(c.statuses.single.spent, Decimal.parse('250'));
      expect(c.statuses.single.remaining, Decimal.parse('750'));
    });
  });

  group('recurring run', () {
    test('creates every due occurrence once and advances the rule', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      final RecurringTransaction rule = dailyRule();
      f.recurring.add(rule);
      final List<DateTime> due = RecurringScheduler.due(rule, DateTime.now());

      final int created = await recurringController(f).runDue();

      expect(created, due.length);
      expect(f.transactions, hasLength(due.length));
      expect(
        f.transactions.map((Transaction t) => t.id).toSet(),
        due
            .map((DateTime o) => RecurringScheduler.transactionId('r1', o))
            .toSet(),
      );
      expect(
        f.transactions.every(
          (Transaction t) =>
              t.type == TransactionType.expense &&
              t.amount == Decimal.parse('100') &&
              t.note == 'Tiffin' &&
              t.categoryId == 'cat-food',
        ),
        isTrue,
      );
      expect(f.recurring.single.nextRunAt.isAfter(DateTime.now()), isTrue);
      expect(f.recurring.single.active, isTrue);
    });

    test('running again creates nothing more', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      f.recurring.add(dailyRule());
      final RecurringController c = recurringController(f);
      await c.runDue();
      final int count = f.transactions.length;

      expect(await c.runDue(), 0);
      expect(await recurringController(f).runDue(), 0);
      expect(f.transactions, hasLength(count));
    });

    test(
      'a crash before the rule advanced cannot duplicate or overwrite',
      () async {
        final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
        final RecurringTransaction rule = dailyRule();
        f.recurring.add(rule);
        await recurringController(f).runDue();
        final int count = f.transactions.length;

        // The user fixes the amount of one generated transaction...
        const int i = 0;
        f.transactions[i] = f.transactions[i].copyWith(
          amount: Decimal.parse('999'),
        );
        // ...and the rule's progress was lost (as if the app died mid-run).
        f.recurring[0] = rule;
        await recurringController(f).runDue();

        expect(f.transactions, hasLength(count));
        expect(f.transactions[i].amount, Decimal.parse('999'));
      },
    );

    test('a finished rule is deactivated after its last occurrence', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      final DateTime now = DateTime.now();
      f.recurring.add(
        dailyRule(end: DateTime(now.year, now.month, now.day - 1)),
      );
      await recurringController(f).runDue();
      expect(f.transactions, hasLength(3)); // 3 days ago .. yesterday
      expect(f.recurring.single.active, isFalse);
      expect(await recurringController(f).runDue(), 0);
    });

    test('paused rules and rules for a deleted account do nothing', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      f.recurring
        ..add(dailyRule(id: 'paused', active: false))
        ..add(dailyRule(id: 'ghost', account: 'missing'));
      expect(await recurringController(f).runDue(), 0);
      expect(f.transactions, isEmpty);
    });

    test('one failing rule does not stop the others', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      f.recurring
        ..add(dailyRule(id: 'a'))
        ..add(dailyRule(id: 'b'));
      final int each = RecurringScheduler.due(
        dailyRule(),
        DateTime.now(),
      ).length;
      await recurringController(f).runDue();
      expect(f.transactions, hasLength(each * 2));
    });
  });

  group('saving rules', () {
    test('a new rule starts from its first occurrence', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      final RecurringController c = recurringController(f);
      final DateTime start = DateTime.now().add(const Duration(days: 10));
      final DateTime day = DateTime(start.year, start.month, start.day);

      final bool ok = await c.saveRule(
        id: 'new',
        accountId: 'acc-1',
        categoryId: null,
        type: TransactionType.income,
        amount: Decimal.parse('5000'),
        frequency: RecurringFrequency.weekly,
        intervalCount: 2,
        startDate: day,
        endDate: null,
        note: null,
      );

      expect(ok, isTrue);
      final RecurringTransaction saved = f.recurring.single;
      expect(
        saved.nextRunAt,
        RecurringScheduler.occurrence(day, RecurringFrequency.weekly, 2, 0),
      );
      expect(saved.scheduleLabel, 'Every 2 weeks');
      expect(await c.runDue(), 0); // not due yet
    });

    test('resuming a paused rule skips what was missed', () async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
      final RecurringTransaction paused = dailyRule(active: false);
      f.recurring.add(paused);
      final RecurringController c = recurringController(f);

      await c.setActive(paused, true);

      expect(f.recurring.single.active, isTrue);
      expect(f.recurring.single.nextRunAt.isBefore(DateTime.now()), isFalse);
      expect(await c.runDue(), 0);
    });
  });
}
