import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:finance_tracker/features/split/views/split_group_detail_view.dart';
import 'package:finance_tracker/features/split/views/split_settlement_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';
import 'split_group_views_test.dart' show contact, dinner;

/// Saving scrolls the form down to its button.
Future<void> _scrollFormUpTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(
      finder,
      -200,
      scrollable: find
          .descendant(
            of: find.byType(SplitSettlementFormView),
            matching: find.byType(Scrollable),
          )
          .first,
    );

Future<void> _start(WidgetTester tester, FakeFinance f) async {
  await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
}

void main() {
  tearDown(Get.reset);

  testWidgets('the header shows the totals and the user\'s net', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await _start(tester, f);

    unawaited(Get.toNamed<void>(AppRoutes.splitGroupDetail, arguments: 'g1'));
    await tester.pumpAndSettle();

    expect(find.byType(SplitGroupDetailView), findsOneWidget);
    expect(find.text('₹1,200.00'), findsNWidgets(2)); // Header + activity row.
    expect(find.text('₹300.00'), findsOneWidget);
    expect(find.text('You get ₹500.00'), findsOneWidget);
  });

  testWidgets('the balances name the parties, a deleted contact included', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    // Neha's contact was deleted on another device (pulled tombstone).
    final Contact neha = f.contacts.firstWhere((Contact c) => c.id == 'c-neha');
    f.contacts[f.contacts.indexOf(neha)] = Contact(
      id: neha.id,
      userId: neha.userId,
      name: neha.name,
      openingBalance: neha.openingBalance,
      openingBalanceType: neha.openingBalanceType,
      createdAt: neha.createdAt,
      updatedAt: neha.updatedAt,
      deletedAt: DateTime(2026, 10, 27),
    );
    await _start(tester, f);

    unawaited(Get.toNamed<void>(AppRoutes.splitGroupDetail, arguments: 'g1'));
    await tester.pumpAndSettle();

    expect(find.text('Amit → You ₹200.00'), findsOneWidget);
    expect(find.text('Deleted contact → You ₹200.00'), findsOneWidget);
    expect(find.text('Amit → Rahul ₹100.00'), findsOneWidget);
  });

  testWidgets('Settle opens the form prefilled and saving removes the row', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await _start(tester, f);

    unawaited(Get.toNamed<void>(AppRoutes.splitGroupDetail, arguments: 'g1'));
    await tester.pumpAndSettle();

    // The first Settle button belongs to the sorted Amit → You pair.
    await tester.tap(find.widgetWithText(FilledButton, 'Settle').first);
    await tester.pumpAndSettle();
    expect(find.byType(SplitSettlementFormView), findsOneWidget);
    expect(find.text('Amit'), findsWidgets);
    expect(find.text('You'), findsWidgets);

    final TextField amount = tester.widget<TextField>(
      find
          .descendant(
            of: find.byType(SplitSettlementFormView),
            matching: find.byType(TextField),
          )
          .first,
    );
    expect(amount.controller!.text, '200');

    await _scrollFormUpTo(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(SplitGroupDetailView), findsOneWidget);
    expect(find.text('Settlement saved'), findsOneWidget);
    expect(find.text('Amit → You ₹200.00'), findsNothing);
    expect(find.text('Amit paid You'), findsOneWidget);
  });

  testWidgets('overpaying flips the pair the other way', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await _start(tester, f);

    unawaited(Get.toNamed<void>(AppRoutes.splitGroupDetail, arguments: 'g1'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Settle').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(SplitSettlementFormView),
            matching: find.byType(TextField),
          )
          .first,
      '250',
    );
    await _scrollFormUpTo(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('You → Amit ₹50.00'), findsOneWidget);
  });

  testWidgets('an empty group asks for the first expense', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance();
    f.contacts.addAll(<Contact>[contact('c-amit', 'Amit')]);
    await f.repositories.split.saveGroup(
      groupId: 'g2',
      name: 'Trip',
      friendContactIds: <String>['c-amit'],
    );
    await _start(tester, f);

    unawaited(Get.toNamed<void>(AppRoutes.splitGroupDetail, arguments: 'g2'));
    await tester.pumpAndSettle();

    expect(find.text('No expenses yet'), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget); // FAB.
  });

  testWidgets('120 activity items load three pages', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance();
    f.contacts.add(contact('c-amit', 'Amit'));
    await f.repositories.split.saveGroup(
      groupId: 'g3',
      name: 'Office',
      friendContactIds: <String>['c-amit'],
    );
    for (int i = 0; i < 120; i++) {
      await f.repositories.split.saveExpense(
        expense: SplitExpense(
          id: 'e-$i',
          userId: '',
          groupId: 'g3',
          title: 'Lunch $i',
          totalAmount: Decimal.parse('10'),
          expenseDate: DateTime(2026, 10, 1 + (i % 20)),
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
            splitExpenseId: 'e-$i',
            memberId: SplitIds.member('g3', null),
            paidAmount: Decimal.parse('10'),
            shareAmount: Decimal.parse('10'),
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      );
    }
    await _start(tester, f);

    unawaited(Get.toNamed<void>(AppRoutes.splitGroupDetail, arguments: 'g3'));
    await tester.pumpAndSettle();
    expect(find.text('Lunch 0'), findsNothing); // Oldest is on the last page.
    expect(find.text('Load more'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Load more'),
      -300,
      scrollable: find
          .descendant(
            of: find.byType(SplitGroupDetailView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Load more'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Load more'),
      -300,
      scrollable: find
          .descendant(
            of: find.byType(SplitGroupDetailView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Load more'), findsNothing); // hasMore is false now.
    expect(find.text('Lunch 0'), findsOneWidget);
  });

  testWidgets('a failed load shows retry', (WidgetTester tester) async {
    final FakeFinance f = FakeFinance();
    f.contacts.add(contact('c-amit', 'Amit'));
    await f.repositories.split.saveGroup(
      groupId: 'g4',
      name: 'Trip',
      friendContactIds: <String>['c-amit'],
    );
    await _start(tester, f);
    f.failAll = const NetworkFailure();

    unawaited(Get.toNamed<void>(AppRoutes.splitGroupDetail, arguments: 'g4'));
    await tester.pumpAndSettle();

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    f.failAll = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No expenses yet'), findsOneWidget);
  });
}
