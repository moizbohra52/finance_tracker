import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/accounts/views/account_detail_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_detail_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_form_view.dart';
import 'package:finance_tracker/widgets/account_list_item.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

/// Tests draw every font as square boxes, far wider than real text. Loading
/// the app's own font files gives text its real width, so a row that is too
/// tight for the font shows up as an overflow error.
Future<void> _loadAppFont() async {
  final FontLoader loader = FontLoader(AppTheme.fontFamily);
  final List<File> files =
      Directory('assets/fonts')
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.ttf'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  for (final File file in files) {
    loader.addFont(
      file.readAsBytes().then((Uint8List b) => ByteData.sublistView(b)),
    );
  }
  await loader.load();
}

/// Scrolls the page to its end, so every section is built and laid out.
Future<void> _scrollThrough(WidgetTester tester) async {
  final Finder page = find
      .byWidgetPredicate(
        (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;
  for (int i = 0; i < 14; i++) {
    await tester.drag(page, const Offset(0, -400), warnIfMissed: false);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, IconData icon) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(icon),
    ),
  );
  await tester.pumpAndSettle();
}

/// Large amounts and long names, which are what push a row past its width.
FakeFinance _busy() {
  final FakeFinance f = FakeFinance()
    ..addAccount('HDFC Savings Account', '1234567.89')
    ..addAccount('Cash Wallet', '5000', id: 'acc-2');
  final DateTime now = DateTime.now();
  f.addTransaction(
    id: 't1',
    type: TransactionType.expense,
    amount: '123456.78',
    categoryId: 'cat-food',
    note: 'Dinner with the whole team after the quarterly review meeting',
    date: now,
  );
  f.addTransaction(
    id: 't2',
    type: TransactionType.income,
    amount: '9876543.21',
    categoryId: 'cat-salary',
    note: 'October salary and festival bonus',
    date: now.subtract(const Duration(days: 1)),
  );
  f.addTransaction(
    id: 't3',
    type: TransactionType.expense,
    amount: '45000',
    categoryId: 'cat-food',
    accountId: 'acc-2',
    date: now.subtract(const Duration(days: 3)),
  );
  f.contacts.add(
    Contact(
      id: 'c1',
      userId: 'user-1',
      name: 'Ramesh Kumar Enterprises Private Limited',
      openingBalance: Decimal.parse('2500000.50'),
      openingBalanceType: 'receivable',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  );
  return f;
}

void main() {
  tearDown(Get.reset);

  testWidgets('the main screens fit a 360 dp wide phone in the app font', (
    WidgetTester tester,
  ) async {
    await _loadAppFont();
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true),
      finance: _busy(),
    );

    // Home, then each tab, scrolled to its end.
    await _scrollThrough(tester);
    for (final IconData tab in <IconData>[
      Icons.receipt_long_outlined,
      Icons.people_outline,
      Icons.insights_outlined,
      Icons.home_outlined,
    ]) {
      await _tapTab(tester, tab);
      await _scrollThrough(tester);
    }

    // An account, with its day headers and rows.
    await tapAndSettle(tester, find.byType(AccountTile).first);
    expect(find.byType(AccountDetailView), findsOneWidget);
    await _scrollThrough(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A transaction's detail screen, then the add form.
    await _tapTab(tester, Icons.receipt_long_outlined);
    await tester.tap(find.byType(TransactionListItem).first);
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailView), findsOneWidget);
    await _scrollThrough(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionFormView), findsOneWidget);
    await _scrollThrough(tester);
  });
}
