import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/accounts/views/account_form_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_detail_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_entry_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_form_view.dart';
import 'package:finance_tracker/features/dashboard/views/dashboard_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_detail_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_form_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

Future<FakeFinance> _start(WidgetTester tester, {FakeFinance? finance}) async {
  final FakeFinance data = finance ?? FakeFinance();
  await pumpApp(
    tester,
    auth: FakeAuthRepository(signedIn: true),
    finance: data,
  );
  return data;
}

FakeFinance _seeded() {
  final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
  f.addTransaction(
    id: 't1',
    type: TransactionType.expense,
    amount: '250',
    categoryId: 'cat-food',
    note: 'Lunch with team',
  );
  f.addTransaction(
    id: 't2',
    type: TransactionType.income,
    amount: '5000',
    categoryId: 'cat-salary',
    note: 'October pay',
  );
  return f;
}

Future<void> _tapNav(WidgetTester tester, IconData icon) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(icon),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  group('home', () {
    testWidgets('empty state asks for a first account and opens the form', (
      WidgetTester tester,
    ) async {
      await _start(tester);
      expect(find.text('Add your first account'), findsOneWidget);

      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountFormView), findsOneWidget);
    });

    testWidgets('shows real balances, khata and recent transactions', (
      WidgetTester tester,
    ) async {
      await _start(tester, finance: _seeded());
      expect(find.text('₹5,750.00'), findsWidgets); // 1000 + 5000 - 250
      expect(find.text('Opening balance ₹1,000.00'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Salary'), 200);
      // Food appears in the spending overview and in recent transactions.
      expect(find.text('Food & Dining'), findsWidgets);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('−₹250.00'), findsOneWidget);
      expect(find.text('+₹5,000.00'), findsOneWidget);
    });

    testWidgets('shows an error with retry when loading fails', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded()..nextError = const NetworkFailure();
      await _start(tester, finance: f);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Current balance'), findsOneWidget);
    });
  });

  group('add account', () {
    testWidgets('creates an account with an opening balance', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await _start(tester);
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Account name'),
        'Wallet',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Opening balance'),
        '1500',
      );
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Add account'),
      );
      await tester.pumpAndSettle();

      expect(f.accounts.single.name, 'Wallet');
      expect(f.accounts.single.openingBalance.toString(), '1500');
      expect(find.byType(DashboardView), findsOneWidget);
      expect(find.text('₹1,500.00'), findsWidgets);
    });

    testWidgets('validates the form before saving', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await _start(tester);
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Add account'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter an account name'), findsOneWidget);
      expect(f.accounts, isEmpty);
    });
  });

  group('transactions', () {
    testWidgets('add expense from home updates the balance', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await _start(tester, finance: _seeded());

      await tester.tap(find.text('Expense').first);
      await tester.pumpAndSettle();
      expect(find.byType(TransactionFormView), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '750.50',
      );
      await tester.tap(find.text('Food & Dining'));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final Transaction saved = f.transactions.last;
      expect(saved.type, TransactionType.expense);
      expect(saved.amount.toString(), '750.5');
      expect(saved.categoryId, 'cat-food');
      expect(find.byType(DashboardView), findsOneWidget);
      expect(find.text('₹4,999.50'), findsWidgets); // 5750 - 750.50
    });

    testWidgets('rejects a zero or missing amount', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await _start(tester, finance: _seeded());
      await tester.tap(find.text('Income').first);
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '0');
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Amount must be more than zero'), findsOneWidget);
      expect(f.transactions, hasLength(2));
    });

    testWidgets('tab lists, searches and clears the search', (
      WidgetTester tester,
    ) async {
      await _start(tester, finance: _seeded());
      await _tapNav(tester, Icons.receipt_long_outlined);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'lunch');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('No matching transactions'), findsOneWidget);
    });

    testWidgets('filters by type from the filter sheet', (
      WidgetTester tester,
    ) async {
      await _start(tester, finance: _seeded());
      await _tapNav(tester, Icons.receipt_long_outlined);

      await tester.tap(find.byTooltip('Filter transactions'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Food & Dining'), findsNothing);
    });

    testWidgets('detail screen shows the record and deletes after confirm', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await _start(tester, finance: _seeded());
      await _tapNav(tester, Icons.receipt_long_outlined);

      await tester.tap(find.text('Food & Dining'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionDetailView), findsOneWidget);
      expect(find.text('Lunch with team'), findsOneWidget);

      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete'));
      expect(find.text('Delete transaction?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        f.transactions.every((Transaction t) => t.deletedAt == null),
        isTrue,
      );

      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
      await tester.pumpAndSettle();

      expect(find.byType(TransactionDetailView), findsNothing);
      expect(
        f.transactions.firstWhere((Transaction t) => t.id == 't1').deletedAt,
        isNotNull,
      );
      expect(find.text('Food & Dining'), findsNothing);
    });

    testWidgets('see all from home opens the list route and goes back', (
      WidgetTester tester,
    ) async {
      await _start(tester, finance: _seeded());
      await tester.scrollUntilVisible(find.text('See all'), 200);
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionListView), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(DashboardView), findsOneWidget);
    });
  });

  group('khata', () {
    testWidgets('add a contact, then record credit and see the balance', (
      WidgetTester tester,
    ) async {
      // Tall enough that the long contact form shows its save button.
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final FakeFinance f = await _start(tester, finance: _seeded());
      await _tapNav(tester, Icons.people_outline);
      expect(find.text('No contacts yet'), findsOneWidget);

      await tester.tap(find.text('Add contact').first);
      await tester.pumpAndSettle();
      expect(find.byType(ContactFormView), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Asha Rao',
      );
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Add contact'),
      );
      await tester.pumpAndSettle();

      expect(f.contacts.single.name, 'Asha Rao');
      expect(find.text('Asha Rao'), findsOneWidget);

      await tester.tap(find.text('Asha Rao'));
      await tester.pumpAndSettle();
      expect(find.byType(ContactDetailView), findsOneWidget);
      expect(find.text('All settled'), findsOneWidget);

      await tapAndSettle(tester, find.text('Add credit'));
      await tester.pumpAndSettle();
      expect(find.byType(ContactEntryView), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '500',
      );
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Save credit'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ContactDetailView), findsOneWidget);
      expect(find.text('You will get'), findsOneWidget);
      expect(find.text('₹500.00'), findsWidgets);
      expect(f.contactTransactions.single.amount.toString(), '500');
    });

    testWidgets('home quick action asks to add a contact when none exist', (
      WidgetTester tester,
    ) async {
      await _start(tester, finance: _seeded());
      await tester.tap(find.text('Credit'));
      await tester.pumpAndSettle();
      expect(find.byType(ContactFormView), findsOneWidget);
    });

    testWidgets('shows an error with retry when contacts fail to load', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await _start(tester, finance: _seeded());
      f.nextError = const NetworkFailure();
      await _tapNav(tester, Icons.people_outline);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
