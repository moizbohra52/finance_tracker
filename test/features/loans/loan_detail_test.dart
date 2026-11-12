import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/widgets/app_dialog.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:finance_tracker/features/loans/views/loan_detail_view.dart';
import 'package:finance_tracker/features/loans/views/loan_list_view.dart';
import 'package:finance_tracker/features/loans/views/loan_payment_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

final DateTime _now = DateTime(2027, 1, 5, 12);

Loan _loan(
  String id,
  String name, {
  LoanMethod method = LoanMethod.emi,
  String principal = '500000',
  String annualRate = '9',
  String emi = '10379.18',
  DateTime? startDate,
  DateTime? closedAt,
}) {
  final bool isEmi = method == LoanMethod.emi;
  final DateTime start = startDate ?? DateTime(2027, 1, 5);
  return Loan(
    id: id,
    userId: 'u',
    direction: LoanDirection.taken,
    method: method,
    name: name,
    accountId: 'acc-1',
    principal: Decimal.parse(principal),
    annualRate: Decimal.parse(annualRate),
    tenureMonths: isEmi ? 60 : null,
    emiAmount: isEmi ? Decimal.parse(emi) : null,
    startDate: start,
    firstDueDate: isEmi ? LoanCalculator.addMonths(start, 1) : null,
    movedMoney: true,
    closedAt: closedAt,
    createdAt: _now,
    updatedAt: _now,
  );
}

LoanPayment _payment(
  String id,
  String loanId,
  DateTime paidAt, {
  String amount = '10379.18',
  String principal = '6629.18',
  String interest = '3750',
}) => LoanPayment(
  id: id,
  userId: 'u',
  loanId: loanId,
  accountId: 'acc-1',
  kind: LoanPaymentKind.scheduled,
  paidAt: paidAt,
  amount: Decimal.parse(amount),
  principalPart: Decimal.parse(principal),
  interestPart: Decimal.parse(interest),
  createdAt: _now,
  updatedAt: _now,
);

Future<FakeFinance> _start(
  WidgetTester tester,
  FakeFinance f, {
  Size size = const Size(800, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
  return f;
}

Future<void> _open(WidgetTester tester, String route, Object argument) async {
  unawaited(Get.toNamed<void>(route, arguments: argument));
  await tester.pumpAndSettle();
}

FakeFinance _finance(
  List<Loan> loans, [
  List<LoanPayment> payments = const [],
]) {
  return FakeFinance()
    ..addAccount('Cash', '1000')
    ..loans.addAll(loans)
    ..loanPayments.addAll(payments);
}

String _fieldText(WidgetTester tester, String label) => tester
    .widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, label),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

Future<void> _confirm(WidgetTester tester) => tapAndSettle(
  tester,
  find.descendant(
    of: find.byType(AppDialog),
    matching: find.widgetWithText(FilledButton, 'Delete'),
  ),
);

void main() {
  tearDown(Get.reset);

  testWidgets('the spec loan shows what is left and its first EMI', (
    WidgetTester tester,
  ) async {
    await _start(tester, _finance(<Loan>[_loan('a', 'HDFC Home Loan')]));
    await _open(tester, AppRoutes.loanDetail, 'a');

    expect(find.byType(LoanDetailView), findsOneWidget);
    expect(find.text('HDFC Home Loan'), findsOneWidget);
    expect(find.text('₹5,00,000.00'), findsOneWidget); // Outstanding.
    expect(find.textContaining('EMI 1 ·'), findsOneWidget);
    expect(find.text('₹10,379.18'), findsWidgets); // One per schedule row.
    expect(find.text('Record payment'), findsOneWidget);
    expect(find.text('Prepay'), findsOneWidget);
    expect(find.text('Close loan'), findsOneWidget);
    expect(find.text('No payments yet'), findsOneWidget);
  });

  testWidgets(
    'Record payment opens the prefilled form; Save updates the loan',
    (WidgetTester tester) async {
      final FakeFinance f = _finance(<Loan>[_loan('a', 'HDFC Home Loan')]);
      await _start(tester, f);
      await _open(tester, AppRoutes.loanDetail, 'a');

      await tapAndSettle(tester, find.text('Record payment'));
      expect(find.byType(LoanPaymentFormView), findsOneWidget);
      expect(_fieldText(tester, 'Amount'), '10379.18');
      expect(_fieldText(tester, 'Principal'), '6629.18');
      expect(_fieldText(tester, 'Interest'), '3750.00');

      await tapAndSettle(tester, find.text('Save'));

      expect(find.byType(LoanDetailView), findsOneWidget);
      expect(f.loanPayments, hasLength(1));
      expect(find.text('₹4,93,370.82'), findsOneWidget);
      expect(find.text('Payment saved'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget); // The new latest payment.
    },
  );

  testWidgets('editing the amount re-splits it and keeps the cursor', (
    WidgetTester tester,
  ) async {
    await _start(tester, _finance(<Loan>[_loan('a', 'HDFC Home Loan')]));
    await _open(tester, AppRoutes.loanPaymentForm, 'a');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '5000',
    );
    await tester.pump();
    expect(_fieldText(tester, 'Amount'), '5000');
    expect(_fieldText(tester, 'Interest'), '3750.00');
    expect(_fieldText(tester, 'Principal'), '1250.00');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Principal'),
      '2000',
    );
    await tester.pump();
    expect(_fieldText(tester, 'Interest'), '3000.00');
  });

  testWidgets('only the latest payment can be edited or deleted', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _finance(
      <Loan>[_loan('a', 'HDFC Home Loan')],
      <LoanPayment>[
        _payment('p1', 'a', DateTime(2027, 2, 5)),
        _payment(
          'p2',
          'a',
          DateTime(2027, 3, 5),
          principal: '6678.92',
          interest: '3700.26',
        ),
      ],
    );
    await _start(tester, f);
    await _open(tester, AppRoutes.loanDetail, 'a');

    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await tapAndSettle(tester, find.text('Delete'));
    expect(find.text('Delete this payment?'), findsOneWidget);
    await _confirm(tester);

    expect(f.loanPayments.where((LoanPayment p) => p.isLive), hasLength(1));
    expect(find.text('Payment deleted'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget); // Now p1 is the latest.
  });

  testWidgets(
    'Edit opens the latest payment in the form and Delete there asks',
    (WidgetTester tester) async {
      final FakeFinance f = _finance(
        <Loan>[_loan('a', 'HDFC Home Loan')],
        <LoanPayment>[_payment('p1', 'a', DateTime(2027, 2, 5))],
      );
      await _start(tester, f);
      await _open(tester, AppRoutes.loanDetail, 'a');

      await tapAndSettle(tester, find.text('Edit'));
      expect(find.byType(LoanPaymentFormView), findsOneWidget);
      expect(_fieldText(tester, 'Amount'), '10379.18');

      await tester.tap(find.byTooltip('Delete payment'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this payment?'), findsOneWidget);
      await _confirm(tester);

      expect(find.byType(LoanDetailView), findsOneWidget);
      expect(f.loanPayments.single.isLive, isFalse);
      expect(find.text('₹5,00,000.00'), findsOneWidget);
    },
  );

  testWidgets(
    'deleting the loan asks first and returns to the list without it',
    (WidgetTester tester) async {
      final FakeFinance f = _finance(
        <Loan>[_loan('a', 'Car loan')],
        <LoanPayment>[_payment('p1', 'a', DateTime(2027, 2, 5))],
      );
      await _start(tester, f);
      await _open(tester, AppRoutes.loans, '');
      await tapAndSettle(tester, find.text('Car loan'));
      expect(find.byType(LoanDetailView), findsOneWidget);

      await tester.tap(find.byTooltip('Delete loan'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This deletes the loan, its 1 payments and their transactions.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(LoanDetailView), findsOneWidget);
      expect(f.loans.single.isLive, isTrue);

      await tester.tap(find.byTooltip('Delete loan'));
      await tester.pumpAndSettle();
      await _confirm(tester);

      expect(find.byType(LoanListView), findsOneWidget);
      expect(find.byType(LoanDetailView), findsNothing);
      expect(find.text('Car loan'), findsNothing);
      expect(f.loans.single.isLive, isFalse);
    },
  );

  testWidgets('the payment route takes a bare loan id and prefills the form', (
    WidgetTester tester,
  ) async {
    await _start(tester, _finance(<Loan>[_loan('a', 'HDFC Home Loan')]));
    await _open(tester, AppRoutes.loanPaymentForm, 'a');

    expect(find.byType(LoanPaymentFormView), findsOneWidget);
    expect(find.text('Record payment'), findsOneWidget);
    expect(_fieldText(tester, 'Amount'), '10379.18');
  });

  testWidgets('Prepay titles the form and starts without an EMI amount', (
    WidgetTester tester,
  ) async {
    await _start(tester, _finance(<Loan>[_loan('a', 'HDFC Home Loan')]));
    await _open(tester, AppRoutes.loanDetail, 'a');

    await tapAndSettle(tester, find.text('Prepay'));
    expect(find.byType(LoanPaymentFormView), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Prepay')),
      findsOneWidget,
    );
    expect(_fieldText(tester, 'Interest'), '0.00');
  });

  testWidgets(
    'Close loan on a monthly loan prefills outstanding plus interest',
    (WidgetTester tester) async {
      final DateTime today = DateTime.now();
      final Loan loan = _loan(
        'm',
        'Loan from Ravi',
        method: LoanMethod.monthlyInterest,
        principal: '100000',
        annualRate: '12',
        startDate: DateTime(today.year, today.month - 3, 1),
      );
      await _start(tester, _finance(<Loan>[loan]));
      await _open(tester, AppRoutes.loanDetail, 'm');
      expect(find.text('Prepay'), findsNothing); // EMI loans only.

      await tapAndSettle(tester, find.text('Close loan'));
      final LoanPart expected = LoanCalculator.suggest(
        loan,
        const <LoanPayment>[],
        kind: LoanPaymentKind.scheduled,
        paidAt: DateTime(today.year, today.month, today.day),
        closing: true,
      );
      expect(expected.interest, greaterThan(Decimal.zero));
      expect(
        _fieldText(tester, 'Amount'),
        (Decimal.parse('100000') + expected.interest).toStringAsFixed(2),
      );
      expect(
        _fieldText(tester, 'Interest'),
        expected.interest.toStringAsFixed(2),
      );
    },
  );

  testWidgets('a closed loan keeps its history but hides the payment actions', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _finance(
      <Loan>[_loan('a', 'Old loan', closedAt: DateTime(2027, 3, 5))],
      <LoanPayment>[
        _payment(
          'p1',
          'a',
          DateTime(2027, 3, 5),
          amount: '503750',
          principal: '500000',
        ),
      ],
    );
    await _start(tester, f);
    await _open(tester, AppRoutes.loanDetail, 'a');

    expect(find.text('Record payment'), findsNothing);
    expect(find.text('Prepay'), findsNothing);
    expect(find.text('Close loan'), findsNothing);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('₹5,03,750.00'), findsOneWidget);
    expect(find.byTooltip('Delete loan'), findsOneWidget);
  });

  testWidgets('the schedule shows 12 rows, then all of them on request', (
    WidgetTester tester,
  ) async {
    await _start(tester, _finance(<Loan>[_loan('a', 'HDFC Home Loan')]));
    await _open(tester, AppRoutes.loanDetail, 'a');

    expect(find.textContaining('EMI 12 ·'), findsOneWidget);
    expect(find.textContaining('EMI 13 ·'), findsNothing);

    await tapAndSettle(tester, find.text('Show all (48)'));
    await tester.scrollUntilVisible(
      find.textContaining('EMI 60 ·'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('EMI 60 ·'), findsOneWidget);
    expect(find.text('Show all (48)'), findsNothing);
  });

  testWidgets('a load failure offers retry, then shows the loan', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _finance(<Loan>[_loan('a', 'HDFC Home Loan')]);
    await _start(tester, f);
    f.failAll = const NetworkFailure();
    await _open(tester, AppRoutes.loanDetail, 'a');

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    f.failAll = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('₹5,00,000.00'), findsOneWidget);
  });

  testWidgets('a long name and big amounts fit a 360 wide screen', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = _finance(
      <Loan>[
        _loan(
          'a',
          'Pradhan Mantri Awas Yojana housing loan from the State Bank of India',
          principal: '99999999.99',
          emi: '9999999.99',
        ),
      ],
      <LoanPayment>[
        _payment(
          'p1',
          'a',
          DateTime(2027, 2, 5),
          amount: '9999999.99',
          principal: '6629999.18',
          interest: '3369999.81',
        ),
      ],
    );
    await _start(tester, f, size: const Size(360, 740));
    await _open(tester, AppRoutes.loanDetail, 'a');
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Delete'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);

    await _open(tester, AppRoutes.loanPaymentForm, 'a');
    expect(tester.takeException(), isNull);
  });
}
