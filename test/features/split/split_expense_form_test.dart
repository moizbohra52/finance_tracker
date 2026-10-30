import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/features/split/controllers/split_expense_controller.dart';
import 'package:finance_tracker/features/split/views/split_expense_form_view.dart';
import 'package:finance_tracker/features/split/views/split_group_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';
import 'split_group_views_test.dart' show contact, dinner;

/// The form is long and its list builds lazily: everything below the fold is
/// scrolled into view before it is tapped or read. The form also holds text
/// fields (each with an inner scrollable), so the drags target the ListView.
Future<void> _scrollUpTo(WidgetTester tester, Finder finder) async {
  final Finder list = find
      .descendant(
        of: find.byType(SplitExpenseFormView),
        matching: find.byType(ListView),
      )
      .first;
  for (int i = 0; i < 20; i++) {
    if (finder.hitTestable().evaluate().isNotEmpty) break;
    await tester.drag(list, const Offset(0, -250));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _field(String label) => find
    .descendant(
      of: find.byType(SplitExpenseFormView),
      matching: find.widgetWithText(TextField, label),
    )
    .first;

/// Picks an option in a bottom-sheet dropdown field.
Future<void> _pickDropdown(
  WidgetTester tester,
  String label,
  String option,
) async {
  await _scrollUpTo(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _tick(WidgetTester tester, String member) async {
  await _scrollUpTo(tester, find.widgetWithText(CheckboxListTile, member));
  await tester.tap(find.widgetWithText(CheckboxListTile, member));
  await tester.pumpAndSettle();
}

Future<void> _start(WidgetTester tester, FakeFinance f) async {
  await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
}

Future<void> _openForm(
  WidgetTester tester, {
  SplitExpenseDetail? existing,
}) async {
  unawaited(
    Get.toNamed<void>(
      AppRoutes.splitExpenseForm,
      arguments: existing == null
          ? const SplitExpenseArgs(groupId: 'g1')
          : SplitExpenseArgs(groupId: 'g1', existing: existing),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillDinner(WidgetTester tester, String rahulPaid) async {
  await tester.enterText(
    find
        .descendant(
          of: find.byType(SplitExpenseFormView),
          matching: find.byType(TextField),
        )
        .first,
    'Dinner',
  );
  await tester.enterText(_field('Total amount'), '1200');
  await tester.tap(find.text('Multiple'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('You'), '800');
  await tester.enterText(_field('Rahul'), rahulPaid);
  // A new expense starts with the whole group ticked.
  await _pickDropdown(tester, 'Category', 'Food & Dining');
  await _pickDropdown(tester, 'Account', 'Cash');
}

void main() {
  tearDown(Get.reset);

  testWidgets('the spec dinner saves end to end', (WidgetTester tester) async {
    final FakeFinance f = await dinner()
      ..addAccount('Cash', '1000');
    await _start(tester, f);
    await _openForm(tester);
    await _fillDinner(tester, '400');

    await _scrollUpTo(
      tester,
      find.text('Your share ₹300.00 · You get ₹500.00'),
    );
    expect(find.text('Your share ₹300.00 · You get ₹500.00'), findsOneWidget);

    await _scrollUpTo(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Expense split saved'), findsOneWidget);
    final SplitExpense saved = f.splitExpenses.firstWhere(
      (SplitExpense e) => e.id != 'e1',
    );
    expect(saved.title, 'Dinner');
    expect(saved.totalAmount, Decimal.parse('1200'));
    expect(saved.splitMode, SplitMode.equal);
    expect(
      f.splitParts.where((SplitPart p) => p.splitExpenseId == saved.id),
      hasLength(4),
    );
  });

  testWidgets('a paid sum one paisa off is refused and stores nothing', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner()
      ..addAccount('Cash', '1000');
    await _start(tester, f);
    await _openForm(tester);
    await _fillDinner(tester, '399.99');

    await _scrollUpTo(
      tester,
      find.text('What was paid must add up to the total'),
    );
    expect(find.text('What was paid must add up to the total'), findsWidgets);

    await _scrollUpTo(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(f.splitExpenses.where((SplitExpense e) => e.id != 'e1'), isEmpty);
    expect(
      f.splitParts.where((SplitPart p) => p.splitExpenseId != 'e1'),
      isEmpty,
    );
  });

  testWidgets('three decimals show the two-decimals message', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner()
      ..addAccount('Cash', '1000');
    await _start(tester, f);
    await _openForm(tester);

    await tester.enterText(
      find
          .descendant(
            of: find.byType(SplitExpenseFormView),
            matching: find.byType(TextField),
          )
          .first,
      'Dinner',
    );
    await tester.enterText(_field('Total amount'), '100.005');

    await _scrollUpTo(tester, find.text('Amounts can have at most 2 decimals'));
    expect(find.text('Amounts can have at most 2 decimals'), findsOneWidget);

    await _scrollUpTo(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(f.splitExpenses.where((SplitExpense e) => e.id != 'e1'), isEmpty);
  });

  testWidgets('percent mode shows the amount left', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner()
      ..addAccount('Cash', '1000');
    await _start(tester, f);
    await _openForm(tester);

    await tester.enterText(
      find
          .descendant(
            of: find.byType(SplitExpenseFormView),
            matching: find.byType(TextField),
          )
          .first,
      'Dinner',
    );
    await tester.enterText(_field('Total amount'), '1200');
    await _scrollUpTo(tester, find.text('%'));
    await tester.tap(find.text('%'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('You'), '50');
    await tester.enterText(_field('Amit'), '30');

    await _scrollUpTo(tester, find.text('20 left'));
    expect(find.text('20 left'), findsOneWidget);
  });

  testWidgets('paying for others needs no category', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner()
      ..addAccount('Cash', '1000');
    await _start(tester, f);
    await _openForm(tester);

    await tester.enterText(
      find
          .descendant(
            of: find.byType(SplitExpenseFormView),
            matching: find.byType(TextField),
          )
          .first,
      'Dinner',
    );
    await tester.enterText(_field('Total amount'), '1200');
    // Everyone starts ticked; untick the user and Rahul, so Amit and Neha
    // share the whole bill.
    await _tick(tester, 'You');
    await _tick(tester, 'Rahul');

    expect(find.text('Choose a category'), findsNothing);
    await _scrollUpTo(
      tester,
      find.text('Your share ₹0.00 · You get ₹1,200.00'),
    );
    expect(find.text('Your share ₹0.00 · You get ₹1,200.00'), findsOneWidget);
  });

  testWidgets('editing reopens in the same mode with the same numbers', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner()
      ..addAccount('Cash', '1000');
    await _start(tester, f);
    final SplitExpenseDetail existing = await f.repositories.split.getExpense(
      'e1',
    );
    await _openForm(tester, existing: existing);

    expect(
      tester.widget<TextField>(_field('Total amount')).controller!.text,
      '1200',
    );
    await _scrollUpTo(tester, _field('You'));
    expect(tester.widget<TextField>(_field('You')).controller!.text, '800');
    expect(tester.widget<TextField>(_field('Rahul')).controller!.text, '400');
    await _scrollUpTo(tester, find.widgetWithText(CheckboxListTile, 'Amit'));
    final int ticked = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .where((CheckboxListTile tile) => tile.value ?? false)
        .length;
    expect(ticked, 4);
  });

  testWidgets('delete confirms and removes the expense', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner()
      ..addAccount('Cash', '1000');
    await _start(tester, f);
    final SplitExpenseDetail existing = await f.repositories.split.getExpense(
      'e1',
    );
    await _openForm(tester, existing: existing);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete this expense?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Split deleted'), findsOneWidget);
    expect(f.splitExpenses.single.deletedAt, isNotNull);
    expect(f.splitParts.where((SplitPart p) => p.isLive), isEmpty);
  });

  testWidgets(
    'the add-transaction sheet offers Split expense and opens the group chooser',
    (WidgetTester tester) async {
      final FakeFinance f = await dinner();
      await _start(tester, f);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.receipt_long_outlined),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Split expense'), findsOneWidget);
      expect(find.text('Share a bill with friends'), findsOneWidget);

      await tester.tap(find.text('Split expense'));
      await tester.pumpAndSettle();

      expect(find.text('Choose a group'), findsOneWidget);
      // Group cards, as on the groups screen, and a way to make a new one.
      expect(find.text('4 members'), findsOneWidget);
      expect(find.text('New group'), findsOneWidget);
      await tester.tap(find.text('Goa'));
      await tester.pumpAndSettle();

      expect(find.byType(SplitExpenseFormView), findsOneWidget);
    },
  );

  testWidgets('with no groups the sheet opens the group form first', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance();
    f.contacts.add(contact('c-amit', 'Amit'));
    await _start(tester, f);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.receipt_long_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split expense'));
    await tester.pumpAndSettle();

    expect(find.byType(SplitGroupFormView), findsOneWidget);
    expect(find.text('Group name'), findsOneWidget);
  });
}
