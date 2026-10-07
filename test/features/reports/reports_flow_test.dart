import 'dart:async';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/widgets/charts.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/accounts/views/account_list_view.dart';
import 'package:finance_tracker/features/profile/views/profile_view.dart';
import 'package:finance_tracker/features/reports/views/reports_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

final DateTime _now = DateTime.now();
final DateTime _lastMonth = DateTime(_now.year, _now.month - 1, 15, 12);

/// This month: income 5,000, expense 250 (food). Last month: expense 400.
FakeFinance _seeded() {
  final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
  f.addTransaction(
    id: 't1',
    type: TransactionType.expense,
    amount: '250',
    categoryId: 'cat-food',
  );
  f.addTransaction(
    id: 't2',
    type: TransactionType.income,
    amount: '5000',
    categoryId: 'cat-salary',
  );
  f.addTransaction(
    id: 't3',
    type: TransactionType.expense,
    amount: '400',
    categoryId: 'cat-food',
    date: _lastMonth,
  );
  return f;
}

Future<void> _open(
  WidgetTester tester,
  FakeFinance finance, {
  ConnectivityService? connectivity,
}) => pumpApp(
  tester,
  auth: FakeAuthRepository(signedIn: true),
  finance: finance,
  connectivityService: connectivity,
);

/// Scrolls the page's main (outermost) vertical list until [finder] shows.
Future<void> _scrollTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(RefreshIndicator),
            matching: find.byType(Scrollable),
          )
          .first,
    );

Future<void> _openReportsTab(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.insights_outlined),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  group('dashboard', () {
    testWidgets('greets the user and shows monthly and spending summaries', (
      WidgetTester tester,
    ) async {
      await _open(tester, _seeded());
      expect(find.text('Asha'), findsOneWidget);
      await _scrollTo(tester, find.text('Spending overview'));
      expect(find.text('This month'), findsOneWidget);
      // Only this month's expense is counted: 250, not 650.
      expect(find.text('₹250.00'), findsWidgets);
      expect(find.text('₹650.00'), findsNothing);
      expect(find.text('+₹4,750.00'), findsOneWidget);
    });

    testWidgets('monthly summary opens the reports route and goes back', (
      WidgetTester tester,
    ) async {
      await _open(tester, _seeded());
      await _scrollTo(tester, find.widgetWithText(TextButton, 'Reports'));
      await tester.tap(find.widgetWithText(TextButton, 'Reports'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportsPage), findsOneWidget);
      expect(find.text('Income vs expense'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ReportsPage), findsNothing);
    });

    testWidgets('avatar opens the profile and accounts action works', (
      WidgetTester tester,
    ) async {
      await _open(tester, _seeded());
      await tester.tap(find.widgetWithText(CircleAvatar, 'A'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileView), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accounts').first);
      await tester.pumpAndSettle();
      expect(find.byType(AccountListView), findsOneWidget);
    });
  });

  group('reports', () {
    testWidgets('shows real totals, charts and category breakdown', (
      WidgetTester tester,
    ) async {
      await _open(tester, _seeded());
      await _openReportsTab(tester);

      expect(find.text('This month'), findsOneWidget); // filter chip
      expect(find.text('₹5,000.00'), findsWidgets);
      expect(find.text('₹250.00'), findsWidgets);
      expect(find.text('+₹4,750.00'), findsOneWidget);
      expect(find.byType(TrendLineChart), findsOneWidget);

      await _scrollTo(tester, find.text('Food & Dining'));
      expect(find.text('Spending by category'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('changing the date filter refreshes the totals', (
      WidgetTester tester,
    ) async {
      await _open(tester, _seeded());
      await _openReportsTab(tester);

      await tester.tap(find.text('Last month'));
      await tester.pumpAndSettle();
      expect(find.text('₹400.00'), findsWidgets);
      expect(find.text('₹5,000.00'), findsNothing);
      expect(find.text('-₹400.00'), findsNothing);
      expect(find.text('−₹400.00'), findsOneWidget);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text('₹400.00'), findsNothing);
      expect(find.text('₹5,000.00'), findsOneWidget); // seeded income is today
    });

    testWidgets('switches the breakdown to income', (
      WidgetTester tester,
    ) async {
      await _open(tester, _seeded());
      await _openReportsTab(tester);
      await _scrollTo(tester, find.text('Spending by category'));

      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<TransactionType>),
          matching: find.text('Income'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Income by category'), findsOneWidget);
      await _scrollTo(tester, find.text('Salary'));
      expect(find.text('Salary'), findsOneWidget);
    });

    testWidgets('empty data shows empty states instead of broken charts', (
      WidgetTester tester,
    ) async {
      await _open(tester, FakeFinance()..addAccount('Cash', '1000'));
      await _openReportsTab(tester);

      expect(find.text('Nothing to show yet'), findsWidgets);
      expect(find.byType(TrendLineChart), findsNothing);
      expect(find.byType(ShareDonut), findsNothing);
      expect(find.byType(IncomeExpenseBarChart), findsNothing);
      expect(find.text('₹0.00'), findsWidgets);
    });

    testWidgets('shows an error with retry', (WidgetTester tester) async {
      final FakeFinance f = _seeded();
      await _open(tester, f);
      f.nextError = const NetworkFailure();
      await _openReportsTab(tester);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Income vs expense'), findsOneWidget);
    });

    testWidgets('shows the offline state when the device is offline', (
      WidgetTester tester,
    ) async {
      final StreamController<NetworkStatus> events =
          StreamController<NetworkStatus>.broadcast();
      addTearDown(events.close);
      final FakeFinance f = _seeded();
      await _open(
        tester,
        f,
        connectivity: ConnectivityService.forTest(
          watch: () => events.stream,
          check: () async => NetworkStatus.offline,
        ),
      );
      f.nextError = const NetworkFailure();
      events.add(NetworkStatus.offline);
      await tester.pumpAndSettle();
      await _openReportsTab(tester);
      expect(find.byType(OfflineState), findsOneWidget);
    });
  });
}
