import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:finance_tracker/features/contacts/views/contact_list_view.dart';
import 'package:finance_tracker/features/split/views/split_group_form_view.dart';
import 'package:finance_tracker/features/split/views/split_group_list_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

Contact contact(String id, String name) => Contact(
  id: id,
  userId: 'u',
  name: name,
  openingBalance: Decimal.zero,
  openingBalanceType: 'receivable',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// Amit, Neha and Rahul, and the Goa group with the spec dinner in it: the
/// user paid 800 of 1200, four equal shares of 300.
Future<FakeFinance> dinner({bool withDerivedRows = false}) async {
  final FakeFinance f = FakeFinance();
  f.contacts.addAll(<Contact>[
    contact('c-amit', 'Amit'),
    contact('c-neha', 'Neha'),
    contact('c-rahul', 'Rahul'),
  ]);
  await f.repositories.split.saveGroup(
    groupId: 'g1',
    name: 'Goa',
    friendContactIds: <String>['c-amit', 'c-neha', 'c-rahul'],
  );
  final String meId = SplitIds.member('g1', null);
  final String amitId = SplitIds.member('g1', 'c-amit');
  final String nehaId = SplitIds.member('g1', 'c-neha');
  final String rahulId = SplitIds.member('g1', 'c-rahul');
  await f.repositories.split.saveExpense(
    expense: SplitExpense(
      id: 'e1',
      userId: '',
      groupId: 'g1',
      title: 'Dinner',
      totalAmount: Decimal.parse('1200'),
      expenseDate: DateTime(2026, 10, 26),
      splitMode: SplitMode.equal,
      categoryId: 'cat-food',
      accountId: 'acc-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    parts: <SplitPart>[
      SplitPart(
        id: '',
        userId: '',
        splitExpenseId: 'e1',
        memberId: meId,
        paidAmount: Decimal.parse('800'),
        shareAmount: Decimal.parse('300'),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      SplitPart(
        id: '',
        userId: '',
        splitExpenseId: 'e1',
        memberId: amitId,
        paidAmount: Decimal.zero,
        shareAmount: Decimal.parse('300'),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      SplitPart(
        id: '',
        userId: '',
        splitExpenseId: 'e1',
        memberId: nehaId,
        paidAmount: Decimal.zero,
        shareAmount: Decimal.parse('300'),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      SplitPart(
        id: '',
        userId: '',
        splitExpenseId: 'e1',
        memberId: rahulId,
        paidAmount: Decimal.parse('400'),
        shareAmount: Decimal.parse('300'),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ],
  );
  if (withDerivedRows) {
    // What the real repository writes for the dinner: the user's share, the
    // balance row (paid for others) and one khata entry per friend's net.
    final DateTime at = DateTime(2026, 10, 26);
    f.transactions.addAll(<Transaction>[
      Transaction(
        id: SplitIds.expenseShare('e1'),
        userId: 'u',
        accountId: 'acc-1',
        categoryId: 'cat-food',
        type: TransactionType.expense,
        amount: Decimal.parse('300'),
        transactionDate: at,
        description: 'Dinner · Goa',
        splitExpenseId: 'e1',
        createdAt: at,
        updatedAt: at,
      ),
      Transaction(
        id: SplitIds.expenseBalance('e1'),
        userId: 'u',
        accountId: 'acc-1',
        type: TransactionType.expense,
        amount: Decimal.parse('500'),
        transactionDate: at,
        description: 'Split: paid for others · Goa',
        splitExpenseId: 'e1',
        createdAt: at,
        updatedAt: at,
      ),
    ]);
    f.contactTransactions.addAll(<ContactTransaction>[
      for (final (String, String, String) friend in <(String, String, String)>[
        ('c-amit', amitId, '200'),
        ('c-neha', nehaId, '200'),
        ('c-rahul', rahulId, '100'),
      ])
        ContactTransaction(
          id: SplitIds.expenseContact('e1', friend.$1),
          userId: 'u',
          contactId: friend.$1,
          type: ContactTransactionType.credit,
          amount: Decimal.parse(friend.$3),
          transactionDate: at,
          note: 'Dinner · Goa',
          splitExpenseId: 'e1',
          createdAt: at,
          updatedAt: at,
        ),
    ]);
  }
  return f;
}

Future<void> _start(WidgetTester tester, FakeFinance f) async {
  await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
}

/// The standalone Khata route, whose app bar holds the Groups action.
Future<void> _openKhata(WidgetTester tester) async {
  unawaited(Get.toNamed<void>(AppRoutes.contacts));
  await tester.pumpAndSettle();
}

Future<void> _openGroups(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(ContactListView),
      matching: find.byIcon(Icons.groups_outlined),
    ),
  );
  await tester.pumpAndSettle();
}

/// Saving scrolls the form down to its button.
Future<void> _scrollFormUpTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(
      finder,
      -200,
      scrollable: find
          .descendant(
            of: find.byType(SplitGroupFormView),
            matching: find.byType(Scrollable),
          )
          .first,
    );

void main() {
  tearDown(Get.reset);

  testWidgets('the Khata app bar has a Groups action that opens the list', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await _start(tester, f);
    await _openKhata(tester);
    expect(find.byType(SplitGroupListView), findsNothing);

    await _openGroups(tester);
    expect(find.byType(SplitGroupListView), findsOneWidget);
    expect(find.text('Goa'), findsOneWidget);
  });

  testWidgets('empty state asks for the first group', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance();
    f.contacts.add(contact('c1', 'Amit'));
    await _start(tester, f);
    await _openKhata(tester);
    await _openGroups(tester);

    expect(find.text('No groups yet'), findsOneWidget);
    expect(
      find.text('Make one for a trip, flatmates or office lunch'),
      findsOneWidget,
    );
    expect(find.text('New group'), findsNWidgets(2)); // Empty state + FAB.
  });

  testWidgets('a seeded group shows its name, members and net', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await _start(tester, f);
    await _openKhata(tester);
    await _openGroups(tester);

    expect(find.text('Goa'), findsOneWidget);
    expect(find.text('4 members'), findsOneWidget);
    expect(find.text('You get ₹500.00'), findsOneWidget);
  });

  testWidgets('a load failure shows retry, which loads on a second try', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance();
    f.contacts.add(contact('c1', 'Amit'));
    await _start(tester, f);
    await _openKhata(tester);
    f.failAll = const NetworkFailure();

    await _openGroups(tester);
    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    f.failAll = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No groups yet'), findsOneWidget);
  });

  testWidgets('creating a group stores it and returns to the list', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance();
    f.contacts.addAll(<Contact>[
      contact('c-amit', 'Amit'),
      contact('c-neha', 'Neha'),
    ]);
    await _start(tester, f);
    await _openKhata(tester);
    await _openGroups(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(SplitGroupFormView),
            matching: find.byType(TextField),
          )
          .first,
      'Flat',
    );
    await tester.tap(find.text('Add friends'));
    await tester.pumpAndSettle();
    expect(find.text('Choose friends'), findsOneWidget);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Amit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Neha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await _scrollFormUpTo(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(SplitGroupListView), findsOneWidget);
    expect(find.text('Flat'), findsOneWidget);
    expect(find.text('3 members'), findsOneWidget);
    expect(f.splitGroups.single.name, 'Flat');
    expect(find.text('Group created'), findsOneWidget);
  });

  testWidgets('a blank name shows the error and stores nothing', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance();
    f.contacts.add(contact('c1', 'Amit'));
    await _start(tester, f);
    await _openKhata(tester);
    await _openGroups(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await _scrollFormUpTo(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Give the group a name'), findsOneWidget);
    expect(f.splitGroups, isEmpty);
  });

  testWidgets(
    'editing shows the delete dialog with the counts and deletes after confirm',
    (WidgetTester tester) async {
      final FakeFinance f = await dinner(withDerivedRows: true);
      await _start(tester, f);
      await _openKhata(tester);
      await _openGroups(tester);
      final List<SplitGroupSummary> groups = await f.repositories.split
          .getGroups();

      unawaited(
        Get.toNamed<void>(AppRoutes.splitGroupForm, arguments: groups.single),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit group'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Delete this group?'), findsOneWidget);
      expect(
        find.text('This deletes 1 expenses and 5 khata entries.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Delete group'));
      await tester.pumpAndSettle();

      expect(find.byType(SplitGroupListView), findsOneWidget);
      expect(find.text('Group deleted'), findsOneWidget);
      expect(f.splitGroups.single.deletedAt, isNotNull);
    },
  );

  testWidgets('the delete dialog can be dismissed and keeps the group', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner(withDerivedRows: true);
    await _start(tester, f);
    await _openKhata(tester);
    await _openGroups(tester);
    final List<SplitGroupSummary> groups = await f.repositories.split
        .getGroups();

    unawaited(
      Get.toNamed<void>(AppRoutes.splitGroupForm, arguments: groups.single),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(f.splitGroups.single.deletedAt, isNull);
  });
}
