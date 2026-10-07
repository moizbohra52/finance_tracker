import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/recurring_scheduler.dart';
import 'package:finance_tracker/features/budgets/controllers/budget_controller.dart';
import 'package:finance_tracker/features/budgets/views/budget_form_view.dart';
import 'package:finance_tracker/features/budgets/views/budget_list_view.dart';
import 'package:finance_tracker/features/dashboard/views/dashboard_view.dart';
import 'package:finance_tracker/features/recurring/views/recurring_form_view.dart';
import 'package:finance_tracker/features/recurring/views/recurring_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

FakeFinance _seeded() {
  final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
  f.addTransaction(
    id: 't1',
    type: TransactionType.expense,
    amount: '250',
    categoryId: 'cat-food',
  );
  return f;
}

Budget _budget({String? category, String amount = '1000'}) {
  final DateTime now = DateTime.now();
  return Budget(
    id: 'b1',
    userId: 'u',
    categoryId: category,
    amount: Decimal.parse(amount),
    periodType: BudgetPeriodType.monthly,
    startDate: DateTime(now.year, now.month),
    endDate: null,
    alert75: true,
    alert90: true,
    alert100: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

RecurringTransaction _rule({bool active = true}) {
  final DateTime start = DateTime.now().add(const Duration(days: 5));
  final DateTime day = DateTime(start.year, start.month, start.day);
  return RecurringTransaction(
    id: 'r1',
    userId: 'u',
    accountId: 'acc-1',
    categoryId: null,
    type: TransactionType.expense,
    amount: Decimal.parse('12000'),
    frequency: RecurringFrequency.monthly,
    intervalCount: 1,
    startDate: day,
    endDate: null,
    nextRunAt: RecurringScheduler.occurrence(
      day,
      RecurringFrequency.monthly,
      1,
      0,
    ),
    active: active,
    note: 'Rent',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

Future<void> _start(WidgetTester tester, FakeFinance f) =>
    pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Opens a dashboard "Plan ahead" tile.
Future<void> _openPlan(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text('Plan ahead'),
    200,
    scrollable: find
        .descendant(
          of: find.byType(RefreshIndicator),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.widgetWithText(PlanTile, title));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  group('budgets', () {
    testWidgets('empty state leads to the form and saves a budget', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded();
      await _start(tester, f);

      await _openPlan(tester, 'Budgets');
      expect(find.byType(BudgetListView), findsOneWidget);
      expect(find.text('No budgets yet'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(BudgetFormView), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Budget amount'),
        '1000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
      await tester.pumpAndSettle();

      expect(f.budgets.single.amount, Decimal.parse('1000'));
      expect(f.budgets.single.categoryId, isNull);
      expect(find.byType(BudgetListView), findsOneWidget);
      expect(find.text('All expenses'), findsOneWidget);
      expect(find.text('₹250.00 of ₹1,000.00'), findsOneWidget);
      expect(find.text('₹750.00 left'), findsOneWidget);
      expect(find.text('On track'), findsOneWidget);
    });

    testWidgets('a category budget shows only its own spending', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded();
      f.addTransaction(
        id: 't2',
        type: TransactionType.expense,
        amount: '300',
        categoryId: 'cat-salary',
      );
      f.budgets.add(_budget(category: 'cat-food', amount: '500'));
      await _start(tester, f);
      await _openPlan(tester, 'Budgets');

      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('₹250.00 of ₹500.00'), findsOneWidget);
      expect(find.text('₹250.00 left'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('warnings and over-budget are labelled, not just coloured', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded();
      f.addTransaction(id: 't2', type: TransactionType.expense, amount: '100');
      f.budgets.add(_budget(amount: '400')); // 350 of 400 = 87.5%
      await _start(tester, f);
      await _openPlan(tester, 'Budgets');
      expect(find.text('75% used'), findsOneWidget);

      f.addTransaction(id: 't3', type: TransactionType.expense, amount: '200');
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.text('Over budget'), findsOneWidget);
      expect(find.text('Over by ₹150.00'), findsOneWidget);
      // The dashboard behind it raised the alerts, once each.
      expect(f.notifications.length, 3);
    });

    testWidgets('editing and deleting a budget', (WidgetTester tester) async {
      await _tall(tester);
      final FakeFinance f = _seeded();
      f.budgets.add(_budget());
      await _start(tester, f);
      await _openPlan(tester, 'Budgets');

      await tester.tap(find.text('All expenses'));
      await tester.pumpAndSettle();
      expect(find.byType(BudgetFormView), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Budget amount'),
        '2000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(f.budgets.single.amount, Decimal.parse('2000'));
      expect(find.text('₹250.00 of ₹2,000.00'), findsOneWidget);

      await tester.tap(find.text('All expenses'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete budget'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this budget?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.budgets, hasLength(1));

      await tester.tap(find.widgetWithText(FilledButton, 'Delete budget'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
      await tester.pumpAndSettle();
      expect(f.budgets, isEmpty);
      expect(find.text('No budgets yet'), findsOneWidget);
    });

    testWidgets('validates the amount and the custom date range', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded();
      await _start(tester, f);
      await _openPlan(tester, 'Budgets');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Budget amount'),
        '500',
      );
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
      await tester.pumpAndSettle();
      expect(find.text('Choose an end date'), findsOneWidget);
      expect(f.budgets, isEmpty);
    });

    testWidgets('shows an error with retry and recovers', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded();
      f.budgets.add(_budget());
      await _start(tester, f);
      // The list is empty in memory when the load fails, so the error shows.
      final BudgetController c = Get.find<BudgetController>();
      c.statuses.clear();
      f.failAll = const NetworkFailure();
      await c.load();
      f.failAll = null;

      await _openPlan(tester, 'Budgets');
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('All expenses'), findsOneWidget);
    });
  });

  group('recurring', () {
    testWidgets('adds a custom "every 2 weeks" schedule', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded();
      await _start(tester, f);

      await _openPlan(tester, 'Recurring');
      expect(find.byType(RecurringListView), findsOneWidget);
      expect(find.text('No recurring transactions'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(RecurringFormView), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '5000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Note (optional)'),
        'Salary advance',
      );
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom…').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Every'), '2');
      await tester.tap(find.text('months'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('weeks').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final RecurringTransaction saved = f.recurring.single;
      expect(saved.frequency, RecurringFrequency.weekly);
      expect(saved.intervalCount, 2);
      expect(saved.amount, Decimal.parse('5000'));
      expect(find.byType(RecurringListView), findsOneWidget);
      expect(find.text('Salary advance'), findsOneWidget);
      expect(find.textContaining('Every 2 weeks'), findsOneWidget);
    });

    testWidgets('a standard monthly schedule saves with interval 1', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded();
      await _start(tester, f);
      await _openPlan(tester, 'Recurring');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '799',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(f.recurring.single.frequency, RecurringFrequency.monthly);
      expect(f.recurring.single.intervalCount, 1);
      expect(find.textContaining('Monthly'), findsOneWidget);
    });

    testWidgets('lists the next run and pauses with the switch', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded();
      f.recurring.add(_rule());
      await _start(tester, f);
      await _openPlan(tester, 'Recurring');

      expect(find.text('Rent'), findsOneWidget);
      expect(find.textContaining('Next '), findsOneWidget);
      expect(find.text('−₹12,000.00'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(f.recurring.single.active, isFalse);
      expect(find.textContaining('Paused'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(f.recurring.single.active, isTrue);
    });

    testWidgets('deleting asks for confirmation', (WidgetTester tester) async {
      await _tall(tester);
      final FakeFinance f = _seeded();
      f.recurring.add(_rule());
      await _start(tester, f);
      await _openPlan(tester, 'Recurring');

      await tester.tap(find.text('Rent'));
      await tester.pumpAndSettle();
      expect(find.byType(RecurringFormView), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete schedule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.recurring, hasLength(1));

      await tester.tap(find.widgetWithText(FilledButton, 'Delete schedule'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
      await tester.pumpAndSettle();
      expect(f.recurring, isEmpty);
      expect(find.text('No recurring transactions'), findsOneWidget);
    });

    testWidgets('due schedules are recorded when the app opens, once', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
      final DateTime now = DateTime.now();
      final DateTime start = DateTime(now.year, now.month, now.day - 2);
      final RecurringTransaction rule = RecurringTransaction(
        id: 'r1',
        userId: 'u',
        accountId: 'acc-1',
        categoryId: 'cat-food',
        type: TransactionType.expense,
        amount: Decimal.parse('100'),
        frequency: RecurringFrequency.daily,
        intervalCount: 1,
        startDate: start,
        endDate: null,
        nextRunAt: RecurringScheduler.occurrence(
          start,
          RecurringFrequency.daily,
          1,
          0,
        ),
        active: true,
        note: 'Tiffin',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      f.recurring.add(rule);
      final int expected = RecurringScheduler.due(rule, now).length;

      await _start(tester, f);

      expect(f.transactions, hasLength(expected));
      final Decimal balance = Decimal.fromInt(1000 - 100 * expected);
      expect(find.text(AppFormatters.money(balance)), findsWidgets);
      expect(find.byType(DashboardView), findsOneWidget);
    });
  });
}
