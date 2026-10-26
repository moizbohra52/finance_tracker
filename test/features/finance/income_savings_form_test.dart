import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/widgets/app_bottom_sheet_dropdown.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/widgets/savings_split_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

SavingsGoal _goal(String id, String name) => SavingsGoal(
  id: id,
  userId: 'user-1',
  name: name,
  targetAmount: Decimal.parse('100000'),
  savedAmount: Decimal.zero,
  targetDate: null,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

SavingsContribution _contribution(String goalId, String amount, {String? id}) =>
    SavingsContribution(
      id: id ?? 'c-$goalId',
      userId: 'user-1',
      transactionId: 't2',
      goalId: goalId,
      amount: Decimal.parse(amount),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

FakeFinance _seeded() {
  final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
  f.savingsGoals.addAll(<SavingsGoal>[
    _goal('g1', 'New phone'),
    _goal('g2', 'Trip'),
  ]);
  return f;
}

/// An income the list can open, with [contributions] already put into goals.
FakeFinance _seededWithIncome(List<SavingsContribution> contributions) {
  final FakeFinance f = _seeded();
  f.addTransaction(
    id: 't2',
    type: TransactionType.income,
    amount: '50000',
    categoryId: 'cat-salary',
    note: 'October pay',
  );
  f.contributions.addAll(contributions);
  return f;
}

Future<void> _start(WidgetTester tester, FakeFinance f) async {
  // Tall enough that the long income form needs no scrolling.
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
}

Future<void> _openIncomeForm(WidgetTester tester) async {
  await tester.tap(find.text('Income').first);
  await tester.pumpAndSettle();
}

Future<void> _openIncomeDetail(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.receipt_long_outlined),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Salary'));
  await tester.pumpAndSettle();
}

Future<void> _openEditForm(WidgetTester tester) async {
  await _openIncomeDetail(tester);
  await tapAndSettle(tester, find.text('Edit'));
}

final Finder _field = find.byType(SavingsSplitField);

Finder _inField(Finder matching) =>
    find.descendant(of: _field, matching: matching);

/// Adds a row with [button], picks [goal] and types [amount].
Future<void> _addRow(
  WidgetTester tester, {
  required String button,
  required String goal,
  required String amount,
}) async {
  await tapAndSettle(tester, find.text(button));
  await tester.tap(_inField(find.byType(BottomSheetDropdown<String>)).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(goal).last);
  await tester.pumpAndSettle();
  await tester.enterText(_inField(find.byType(TextFormField)).last, amount);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('income form puts part of the income into two goals', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _seeded();
    await _start(tester, f);
    await _openIncomeForm(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '50000',
    );
    await tester.tap(find.text('Salary'));
    await tester.pumpAndSettle();
    await _addRow(
      tester,
      button: 'Put some in savings',
      goal: 'New phone',
      amount: '5000',
    );
    await _addRow(tester, button: 'Another goal', goal: 'Trip', amount: '3000');

    expect(find.text('₹8,000.00 to savings · ₹42,000.00 left'), findsOneWidget);
    // Every goal is used.
    expect(find.text('Another goal'), findsNothing);

    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final List<SavingsContribution> live = f.contributions
        .where((SavingsContribution c) => c.deletedAt == null)
        .toList();
    expect(live, hasLength(2));
    expect(
      <String, Decimal>{
        for (final SavingsContribution c in live) c.goalId: c.amount,
      },
      <String, Decimal>{
        'g1': Decimal.parse('5000'),
        'g2': Decimal.parse('3000'),
      },
    );
    expect(f.transactions.single.id, live.first.transactionId);
  });

  testWidgets('detail shows where the income went', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _seededWithIncome(<SavingsContribution>[
      _contribution('g1', '5000'),
      _contribution('g2', '3000'),
    ]);
    await _start(tester, f);
    await _openIncomeDetail(tester);

    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('New phone ₹5,000.00 · Trip ₹3,000.00'), findsOneWidget);
  });

  testWidgets('detail has no Savings row for an income without savings', (
    WidgetTester tester,
  ) async {
    await _start(tester, _seededWithIncome(const <SavingsContribution>[]));
    await _openIncomeDetail(tester);

    expect(find.text('Savings'), findsNothing);
  });

  testWidgets('detail names a goal that is not loaded as Savings goal', (
    WidgetTester tester,
  ) async {
    await _start(
      tester,
      _seededWithIncome(<SavingsContribution>[_contribution('gone', '700')]),
    );
    await _openIncomeDetail(tester);

    expect(find.text('Savings goal ₹700.00'), findsOneWidget);
  });

  testWidgets('savings above the income show the error and do not save', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _seeded();
    await _start(tester, f);
    await _openIncomeForm(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '50000',
    );
    await tester.tap(find.text('Salary'));
    await tester.pumpAndSettle();
    await _addRow(
      tester,
      button: 'Put some in savings',
      goal: 'New phone',
      amount: '60000',
    );
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text("Savings can't be more than the income"), findsOneWidget);
    expect(f.transactions, isEmpty);
    expect(f.contributions, isEmpty);
  });

  testWidgets('the section is hidden for an expense', (
    WidgetTester tester,
  ) async {
    await _start(tester, _seeded());
    await tester.tap(find.text('Expense').first);
    await tester.pumpAndSettle();

    expect(find.text('Put some in savings'), findsNothing);
    expect(_field, findsNothing);
  });

  testWidgets('a row can be removed', (WidgetTester tester) async {
    final FakeFinance f = _seeded();
    await _start(tester, f);
    await _openIncomeForm(tester);
    await _addRow(
      tester,
      button: 'Put some in savings',
      goal: 'Trip',
      amount: '300',
    );
    expect(find.text('Put some in savings'), findsNothing);

    await tapAndSettle(tester, find.byTooltip('Remove'));

    expect(find.text('Put some in savings'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing an income preloads its savings rows', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _seededWithIncome(<SavingsContribution>[
      _contribution('g1', '5000'),
    ]);
    await _start(tester, f);
    await _openEditForm(tester);

    expect(_inField(find.text('New phone')), findsOneWidget);
    expect(_inField(find.text('5000')), findsOneWidget);
    expect(find.text('₹5,000.00 to savings · ₹45,000.00 left'), findsOneWidget);

    // Saving without a change must keep the savings: the controller diffs
    // against the stored rows even when the form passes none.
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Save changes'),
    );
    await tester.pumpAndSettle();

    final List<SavingsContribution> live = f.contributions
        .where((SavingsContribution c) => c.deletedAt == null)
        .toList();
    expect(live.single.id, 'c-g1');
    expect(live.single.amount, Decimal.parse('5000'));
  });

  testWidgets('two live rows for one goal show as one and Save removes the '
      'extra', (WidgetTester tester) async {
    final FakeFinance f = _seededWithIncome(<SavingsContribution>[
      _contribution('g1', '5000'),
      _contribution('g1', '5000', id: 'c-g1-dup'),
    ]);
    await _start(tester, f);
    await _openEditForm(tester);

    expect(_inField(find.byType(BottomSheetDropdown<String>)), findsOneWidget);
    expect(_inField(find.text('New phone')), findsOneWidget);
    expect(_inField(find.text('5000')), findsOneWidget);

    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Save changes'),
    );
    await tester.pumpAndSettle();

    expect(find.text('This goal is already used'), findsNothing);
    final List<SavingsContribution> live = f.contributions
        .where((SavingsContribution c) => c.deletedAt == null)
        .toList();
    expect(live.single.id, 'c-g1');
    expect(live.single.amount, Decimal.parse('5000'));
    expect(
      f.contributions.singleWhere(
        (SavingsContribution c) => c.id == 'c-g1-dup',
      ),
      isA<SavingsContribution>().having(
        (SavingsContribution c) => c.deletedAt,
        'deletedAt',
        isNotNull,
      ),
    );
  });

  testWidgets('an income whose savings could not be loaded is not saved', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _seededWithIncome(<SavingsContribution>[
      _contribution('g1', '5000'),
    ]);
    await _start(tester, f);
    await _openIncomeDetail(tester);
    // The form's first read is the savings: saving without them would drop
    // them.
    f.nextError = const NetworkFailure();
    await tapAndSettle(tester, find.text('Edit'));

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(_field, findsNothing);
    final DateTime updatedBefore = f.transactions.single.updatedAt;
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Save changes'),
    );
    await tester.pumpAndSettle();
    expect(f.transactions.single.updatedAt, updatedBefore);
    expect(
      f.contributions.where((SavingsContribution c) => c.deletedAt == null),
      hasLength(1),
    );
  });

  testWidgets(
    'a non-app error while loading savings still shows a message and blocks Save',
    (WidgetTester tester) async {
      final FakeFinance f = _seededWithIncome(<SavingsContribution>[
        _contribution('g1', '5000'),
      ]);
      await _start(tester, f);
      await _openIncomeDetail(tester);
      // A local database or decoding error is not an AppException.
      f.contributionsError = StateError('disk');
      await tapAndSettle(tester, find.text('Edit'));

      expect(find.text(const UnexpectedFailure().message), findsOneWidget);
      expect(_field, findsNothing);
      final DateTime updatedBefore = f.transactions.single.updatedAt;
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      await tester.pumpAndSettle();
      expect(f.transactions.single.updatedAt, updatedBefore);
      expect(
        f.contributions.where((SavingsContribution c) => c.deletedAt == null),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'a preloaded row whose goal is not loaded shows a fallback label',
    (WidgetTester tester) async {
      final FakeFinance f = _seededWithIncome(<SavingsContribution>[
        _contribution('gone', '700'),
      ]);
      await _start(tester, f);
      await _openEditForm(tester);

      // The dropdown's own label and the fallback name.
      expect(_inField(find.text('Savings goal')), findsNWidgets(2));
      expect(_inField(find.text('700')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
