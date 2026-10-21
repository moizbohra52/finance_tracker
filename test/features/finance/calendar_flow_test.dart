import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/views/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

/// The day list sits below the month grid, so it may need a scroll.
Future<void> _scrollTo(WidgetTester tester, Finder finder, {bool up = false}) =>
    tester.scrollUntilVisible(
      finder,
      up ? -200 : 200,
      scrollable: find
          .descendant(
            of: find.byType(CalendarView),
            matching: find.byType(Scrollable),
          )
          .first,
    );

void main() {
  tearDown(Get.reset);

  testWidgets('opens from the transactions tab and shows each day', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.now();
    final FakeFinance finance = FakeFinance()..addAccount('Cash', '0');
    finance
      ..addTransaction(
        id: 'today',
        type: TransactionType.expense,
        amount: '400',
        categoryId: 'cat-food',
        date: DateTime(now.year, now.month, now.day, 9),
      )
      ..addTransaction(
        id: 'last-month',
        type: TransactionType.expense,
        amount: '700',
        categoryId: 'cat-food',
        date: DateTime(now.year, now.month - 1, 10, 9),
      );
    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true),
      finance: finance,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.receipt_long_outlined),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Calendar view'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarView), findsOneWidget);
    expect(find.text('400'), findsOneWidget, reason: "today's cell");
    await _scrollTo(tester, find.text('Food & Dining'));
    expect(
      find.text('Food & Dining'),
      findsOneWidget,
      reason: 'opens on today',
    );

    await _scrollTo(tester, find.byTooltip('Previous month'), up: true);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('700'), findsOneWidget);
    await _scrollTo(tester, find.text('Nothing on this day'));
    expect(find.text('Nothing on this day'), findsOneWidget, reason: 'the 1st');

    await _scrollTo(tester, find.text('10'), up: true);
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Food & Dining'));
    expect(find.text('Food & Dining'), findsOneWidget);
  });
}
