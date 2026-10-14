import 'package:finance_tracker/core/widgets/app_dialog.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/categories/views/category_form_view.dart';
import 'package:finance_tracker/features/categories/views/category_list_view.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

Future<FakeFinance> _start(WidgetTester tester) async {
  final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
  await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
  return f;
}

Future<void> _go(WidgetTester tester, String route, {Object? arguments}) async {
  Get.toNamed<void>(route, arguments: arguments)?.ignore();
  await tester.pumpAndSettle();
}

Finder _nameField() => find.widgetWithText(TextFormField, 'Name');

Iterable<Category> _own(FakeFinance f) =>
    f.categories.where((Category c) => !c.isSystem && c.deletedAt == null);

void main() {
  tearDown(Get.reset);

  testWidgets('settings opens categories; built-in ones are read-only', (
    WidgetTester tester,
  ) async {
    await _start(tester);
    await _go(tester, AppRoutes.settings);

    await tapAndSettle(tester, find.text('Categories'));

    expect(find.byType(CategoryListView), findsOneWidget);
    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.textContaining('Add your own'), findsOneWidget);

    // A built-in row opens nothing.
    await tester.tap(find.text('Food & Dining'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryFormView), findsNothing);
  });

  testWidgets('adds, renames and deletes an own category', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await _start(tester);
    await _go(tester, AppRoutes.categories);

    await tapAndSettle(
      tester,
      find.widgetWithText(FloatingActionButton, 'Add category'),
    );
    await tester.enterText(_nameField(), 'Pet care');
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Add category'),
    );

    expect(find.text('Pet care'), findsOneWidget);
    expect(_own(f).single.name, 'Pet care');
    expect(_own(f).single.type, CategoryType.expense);

    await tapAndSettle(tester, find.text('Pet care'));
    await tester.enterText(_nameField(), 'Pets');
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Save changes'),
    );
    expect(find.text('Pets'), findsOneWidget);
    expect(_own(f).single.name, 'Pets');

    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Delete category'),
    );
    await tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      ),
    );

    expect(_own(f), isEmpty);
    expect(find.text('Pets'), findsNothing);
  });

  testWidgets('refuses a name that is already taken', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await _start(tester);
    await _go(tester, AppRoutes.categoryForm);

    await tester.enterText(_nameField(), 'food & dining');
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Add category'),
    );

    expect(
      find.text('A category with this name already exists'),
      findsOneWidget,
    );
    expect(_own(f), isEmpty);
  });

  testWidgets('a category made from the expense form is selected there', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await _start(tester);
    await _go(
      tester,
      AppRoutes.transactionForm,
      arguments: const TransactionFormArgs(),
    );

    await tapAndSettle(tester, find.widgetWithText(ActionChip, 'New'));
    expect(find.byType(CategoryFormView), findsOneWidget);
    await tester.enterText(_nameField(), 'Gym');
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Add category'),
    );

    expect(_own(f).single.type, CategoryType.expense);
    final ChoiceChip gym = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Gym'),
    );
    expect(gym.selected, isTrue);
  });

  testWidgets('category chips show no check mark when selected', (
    WidgetTester tester,
  ) async {
    await _start(tester);
    await _go(
      tester,
      AppRoutes.transactionForm,
      arguments: const TransactionFormArgs(type: TransactionType.expense),
    );

    await tapAndSettle(
      tester,
      find.widgetWithText(ChoiceChip, 'Food & Dining'),
    );

    final ChoiceChip chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Food & Dining'),
    );
    expect(chip.selected, isTrue);
    expect(chip.showCheckmark, isFalse);
    // Selection is marked by a thicker border, not colour alone.
    expect(chip.side?.width, greaterThan(1));
  });
}
