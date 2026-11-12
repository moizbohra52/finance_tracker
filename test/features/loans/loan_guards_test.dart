import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/contacts/controller/contact_detail_controller.dart';
import 'package:finance_tracker/features/contacts/views/contact_detail_view.dart';
import 'package:finance_tracker/features/loans/views/loan_detail_view.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/views/transaction_detail_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

final DateTime _now = DateTime(2027, 1, 5, 12);

Contact _contact(String id, String name) => Contact(
  id: id,
  userId: 'u',
  name: name,
  openingBalance: Decimal.zero,
  openingBalanceType: 'receivable',
  createdAt: _now,
  updatedAt: _now,
);

Loan _loan(
  String id,
  String name, {
  String? contactId,
  LoanDirection direction = LoanDirection.given,
  String principal = '50000',
}) => Loan(
  id: id,
  userId: 'u',
  direction: direction,
  method: LoanMethod.monthlyInterest,
  name: name,
  contactId: contactId,
  accountId: 'acc-1',
  principal: Decimal.parse(principal),
  annualRate: Decimal.parse('12'),
  startDate: DateTime(2027, 1, 5),
  movedMoney: true,
  createdAt: _now,
  updatedAt: _now,
);

/// Ravi owes 500 on the khata and has a 50,000 loan (given by the user); a
/// derived row of that loan and a plain expense sit in the transactions.
FakeFinance _finance() {
  final FakeFinance f = FakeFinance()
    ..addAccount('Cash', '1000')
    ..contacts.addAll(<Contact>[
      _contact('c-ravi', 'Ravi'),
      _contact('c-zoya', 'Zoya'),
    ]);
  f.contactTransactions.add(
    ContactTransaction(
      id: 'e1',
      userId: 'u',
      contactId: 'c-ravi',
      type: ContactTransactionType.credit,
      amount: Decimal.parse('500'),
      transactionDate: DateTime(2027, 1, 2),
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  f.addTransaction(
    id: 'plain-tx',
    type: TransactionType.expense,
    amount: '250',
    note: 'Solo lunch',
  );
  f.loans.add(_loan('l1', 'Bike loan', contactId: 'c-ravi'));
  f.transactions.add(
    Transaction(
      id: 'loan-tx',
      userId: 'u',
      accountId: 'acc-1',
      type: TransactionType.payment_made,
      amount: Decimal.parse('50000'),
      transactionDate: DateTime.now(),
      loanId: 'l1',
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return f;
}

Future<void> _start(
  WidgetTester tester,
  FakeFinance f, {
  Size size = const Size(800, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
}

Future<void> _open(WidgetTester tester, String route, Object argument) async {
  unawaited(Get.toNamed<void>(route, arguments: argument));
  await tester.pumpAndSettle();
}

Finder _inContact(Finder f) =>
    find.descendant(of: find.byType(ContactDetailView), matching: f);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test('deleteTransaction refuses a loan row and deletes nothing', () async {
    Get.testMode = true;
    final FakeFinance f = _finance();
    final TransactionController controller = TransactionController(
      f.repositories.transactions,
      f.repositories.accounts,
      f.repositories.categories,
      DataChangeNotifier(),
    );
    Get.put(controller);
    await controller.load();

    expect(await controller.deleteTransaction('loan-tx'), isFalse);
    expect(
      controller.deletion.error.value,
      'Open the loan to change or delete it',
    );
    expect(
      f.transactions.any(
        (Transaction t) => t.id == 'loan-tx' && t.deletedAt == null,
      ),
      isTrue,
    );
    expect(await controller.deleteTransaction('plain-tx'), isTrue);
  });

  testWidgets('a loan transaction shows Open loan, not Edit or Delete', (
    WidgetTester tester,
  ) async {
    await _start(tester, _finance());
    await _open(tester, AppRoutes.transactionDetail, 'loan-tx');

    expect(find.byType(TransactionDetailView), findsOneWidget);
    expect(find.text('Open loan'), findsOneWidget);
    expect(find.text('Remind me'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);

    await tester.tap(find.text('Open loan'));
    await tester.pumpAndSettle();
    expect(find.byType(LoanDetailView), findsOneWidget);
    expect(find.text('Bike loan'), findsWidgets);
  });

  testWidgets('a plain transaction keeps Edit and Delete', (
    WidgetTester tester,
  ) async {
    await _start(tester, _finance());
    await _open(tester, AppRoutes.transactionDetail, 'plain-tx');

    expect(find.text('Open loan'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a loan row cannot be swiped away in the Transactions tab', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _finance();
    await _start(tester, f);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.receipt_long_outlined),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find
          .byWidgetPredicate(
            (Widget w) =>
                w is TransactionListItem && w.transaction.isLoanDerived,
          )
          .first,
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete transaction?'), findsNothing);
    expect(
      f.transactions.where((Transaction t) => t.deletedAt != null),
      isEmpty,
    );
  });

  testWidgets('a contact lists their loans and the balance ignores them', (
    WidgetTester tester,
  ) async {
    await _start(tester, _finance());
    await _open(tester, AppRoutes.contactDetail, 'c-ravi');

    expect(_inContact(find.text('Loans')), findsOneWidget);
    expect(_inContact(find.text('Bike loan')), findsOneWidget);
    expect(_inContact(find.text('₹50,000.00')), findsOneWidget);
    expect(_inContact(find.text('Loan you gave')), findsOneWidget);
    // Only the 500 khata credit is in the balance.
    expect(
      Get.find<ContactDetailController>(tag: 'c-ravi').balance.value,
      Decimal.parse('500'),
    );

    await tester.tap(_inContact(find.text('Bike loan')));
    await tester.pumpAndSettle();
    expect(find.byType(LoanDetailView), findsOneWidget);
  });

  testWidgets('a contact without loans has no Loans section', (
    WidgetTester tester,
  ) async {
    await _start(tester, _finance());
    await _open(tester, AppRoutes.contactDetail, 'c-zoya');

    expect(find.byType(ContactDetailView), findsOneWidget);
    expect(_inContact(find.text('Loans')), findsNothing);
  });

  testWidgets('a long loan name and big amounts fit a 360 wide screen', (
    WidgetTester tester,
  ) async {
    await _start(
      tester,
      FakeFinance()
        ..addAccount('Cash', '1000')
        ..contacts.add(_contact('c-ravi', 'Ravi'))
        ..loans.add(
          _loan(
            'l1',
            'Pradhan Mantri Awas Yojana housing loan from the State Bank of India',
            contactId: 'c-ravi',
            direction: LoanDirection.taken,
            principal: '99999999.99',
          ),
        ),
      size: const Size(360, 740),
    );
    // The test font is far wider than the real one, so the screen's own
    // button rows overflow in it; only the Loans rows are checked.
    final List<String> errors = <String>[];
    final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) => errors.add('$d');
    addTearDown(() => FlutterError.onError = previous);
    await _open(tester, AppRoutes.contactDetail, 'c-ravi');

    expect(_inContact(find.text('Loans')), findsOneWidget);
    expect(_inContact(find.text('₹9,99,99,999.99')), findsOneWidget);
    expect(
      errors.where((String e) => e.contains('app_list_tile.dart')),
      isEmpty,
    );
  });
}
