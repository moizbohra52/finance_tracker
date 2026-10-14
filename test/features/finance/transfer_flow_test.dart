import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/widgets/app_dialog.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
import 'package:finance_tracker/features/transactions/views/transaction_detail_view.dart';
import 'package:finance_tracker/features/transactions/views/transfer_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

/// Cash 1,000 and Bank 5,000.
FakeFinance _twoAccounts() => FakeFinance()
  ..addAccount('Cash', '1000')
  ..addAccount('Bank', '5000', id: 'acc-2');

/// Adds a stored transfer of 300 from Cash to Bank.
void _seedTransfer(FakeFinance f) {
  final TransferLegs legs = TransferLegs.build(
    transferId: 'tr-1',
    outgoingId: 'tr-1-out',
    incomingId: 'tr-1-in',
    fromAccountId: 'acc-1',
    toAccountId: 'acc-2',
    amount: Decimal.parse('300'),
    date: DateTime.now(),
    now: DateTime.now(),
  );
  f.transactions.addAll(<Transaction>[legs.outgoing, legs.incoming]);
}

List<Transaction> _live(FakeFinance f) =>
    f.transactions.where((Transaction t) => t.deletedAt == null).toList();

Future<void> _start(WidgetTester tester, FakeFinance f) =>
    pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);

Future<void> _openDetail(WidgetTester tester, String id) async {
  Get.toNamed<void>(AppRoutes.transactionDetail, arguments: id)?.ignore();
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('moves money between accounts and keeps the total', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _twoAccounts();
    await _start(tester, f);
    expect(find.text('₹6,000.00'), findsWidgets);

    await tapAndSettle(tester, find.text('Transfer'));
    expect(find.byType(TransferFormView), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '300');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Transfer'));

    final List<Transaction> legs = _live(f);
    expect(legs, hasLength(2));
    final Transaction out = legs.firstWhere(
      (Transaction t) => t.type == TransactionType.transfer_out,
    );
    final Transaction into = legs.firstWhere(
      (Transaction t) => t.type == TransactionType.transfer_in,
    );
    expect(out.accountId, 'acc-1');
    expect(into.accountId, 'acc-2');
    expect(out.transferId, into.transferId);
    expect(out.amount, Decimal.parse('300'));
    expect(find.text('Transfer saved'), findsOneWidget);
    // Net worth is unchanged: the money only moved. (Tapping the action
    // scrolled the home list, so scroll back up to the balance card.)
    await tester.scrollUntilVisible(
      find.text('₹6,000.00'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('₹6,000.00'), findsWidgets);
  });

  testWidgets('needs a second account to transfer', (
    WidgetTester tester,
  ) async {
    await _start(tester, FakeFinance()..addAccount('Cash', '1000'));

    await tapAndSettle(tester, find.text('Transfer'));

    expect(find.text('Add another account'), findsOneWidget);
  });

  testWidgets('the destination list leaves out the source account', (
    WidgetTester tester,
  ) async {
    await _start(tester, _twoAccounts());
    Get.toNamed<void>(AppRoutes.transferForm)?.ignore();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();

    // The sheet offers Bank only once (the current value) and never Cash,
    // which is sending the money.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Cash'),
      ),
      findsNothing,
    );
  });

  testWidgets('a transfer reads as one movement and deletes as one', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _twoAccounts();
    _seedTransfer(f);
    await _start(tester, f);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.receipt_long_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('To Bank'), findsOneWidget);
    expect(find.text('From Cash'), findsOneWidget);

    await tapAndSettle(tester, find.text('To Bank'));
    expect(find.byType(TransactionDetailView), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Category'), findsNothing);

    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('Delete transfer?'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      ),
    );

    expect(_live(f), isEmpty, reason: 'both legs are gone');
    expect(find.text('Transfer deleted'), findsOneWidget);
  });

  testWidgets('editing the amount keeps the same transfer', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _twoAccounts();
    _seedTransfer(f);
    await _start(tester, f);
    await _openDetail(tester, 'tr-1-out');

    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Edit'));
    expect(find.text('Edit transfer'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '450');
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Save changes'),
    );

    final List<Transaction> legs = _live(f);
    expect(legs, hasLength(2));
    expect(legs.map((Transaction t) => t.transferId).toSet(), <String>{'tr-1'});
    expect(legs.map((Transaction t) => t.amount).toSet(), <Decimal>{
      Decimal.parse('450'),
    });
    // The same rows were updated, so the detail screen stays open.
    expect(find.byType(TransactionDetailView), findsOneWidget);
    expect(find.text('Transfer updated'), findsOneWidget);
  });

  testWidgets('swapping the accounts replaces the transfer', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _twoAccounts();
    _seedTransfer(f);
    await _start(tester, f);
    await _openDetail(tester, 'tr-1-out');

    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Edit'));
    await tapAndSettle(tester, find.byTooltip('Swap accounts'));
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Save changes'),
    );

    final List<Transaction> legs = _live(f);
    expect(legs, hasLength(2));
    expect(legs.first.transferId, isNot('tr-1'));
    expect(
      legs
          .firstWhere((Transaction t) => t.type == TransactionType.transfer_out)
          .accountId,
      'acc-2',
    );
    // The old legs are tombstoned, so their detail screen was closed too.
    expect(find.byType(TransactionDetailView), findsNothing);
  });
}
