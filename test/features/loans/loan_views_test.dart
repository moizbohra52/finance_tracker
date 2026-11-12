import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:finance_tracker/features/loans/controllers/loan_form_controller.dart';
import 'package:finance_tracker/features/loans/views/loan_form_view.dart';
import 'package:finance_tracker/features/loans/views/loan_list_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

Loan _loan(
  String id,
  String name, {
  LoanDirection direction = LoanDirection.taken,
  String principal = '500000',
  String accountId = 'acc-1',
}) {
  final DateTime now = DateTime(2027, 1, 5, 12);
  return Loan(
    id: id,
    userId: 'u',
    direction: direction,
    method: LoanMethod.emi,
    name: name,
    accountId: accountId,
    principal: Decimal.parse(principal),
    annualRate: Decimal.parse('9'),
    tenureMonths: 60,
    emiAmount: Decimal.parse('10379.18'),
    startDate: DateTime(2027, 1, 5),
    firstDueDate: DateTime(2027, 2, 5),
    movedMoney: true,
    createdAt: now,
    updatedAt: now,
  );
}

Future<FakeFinance> _start(WidgetTester tester, FakeFinance f) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
  return f;
}

Future<void> _openList(WidgetTester tester) async {
  await tapAndSettle(tester, find.text('Loans'));
}

void main() {
  tearDown(Get.reset);

  testWidgets('the Home Loans tile opens the list, empty at first', (
    WidgetTester tester,
  ) async {
    await _start(tester, FakeFinance()..addAccount('Cash', '1000'));
    await _openList(tester);

    expect(find.byType(LoanListView), findsOneWidget);
    expect(find.text('No loans yet'), findsOneWidget);
    expect(find.text('Add loan'), findsNWidgets(2)); // Empty state + FAB.
  });

  testWidgets('adding the spec loan fills the EMI and lists the loan', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
    await _start(tester, f);
    await _openList(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(LoanFormView), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Loan name'),
      'HDFC Home Loan',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Principal'),
      '500000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Interest rate (% a year)'),
      '9',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tenure (months)'),
      '60',
    );
    await tester.pumpAndSettle();
    expect(find.text('10379.18'), findsOneWidget);

    await tapAndSettle(tester, find.text('Save'));

    expect(find.byType(LoanListView), findsOneWidget);
    expect(f.loans, hasLength(1));
    expect(find.text('HDFC Home Loan'), findsOneWidget);
    expect(find.text('₹5,00,000.00'), findsWidgets);
    final String due = AppFormatters.date(
      LoanCalculator.addMonths(f.loans.single.startDate, 1),
    );
    expect(find.text('Next $due · ₹10,379.18'), findsOneWidget);
  });

  testWidgets('the Given segment lists only given loans', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance()
      ..addAccount('Cash', '1000')
      ..loans.addAll(<Loan>[
        _loan('a', 'Car loan'),
        _loan(
          'b',
          'Loan to Amit',
          direction: LoanDirection.given,
          principal: '20000',
        ),
      ]);
    await _start(tester, f);
    await _openList(tester);
    expect(find.text('Car loan'), findsOneWidget);
    expect(find.text('Loan to Amit'), findsNothing);

    await tester.tap(find.text('Given'));
    await tester.pumpAndSettle();
    expect(find.text('Car loan'), findsNothing);
    expect(find.text('Loan to Amit'), findsOneWidget);
  });

  testWidgets('a load failure shows retry', (WidgetTester tester) async {
    final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
    await _start(tester, f);
    f.failAll = const NetworkFailure();
    await _openList(tester);

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    f.failAll = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No loans yet'), findsOneWidget);
  });

  testWidgets('terms are locked after the first payment, the name is not', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2027, 1, 5, 12);
    final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
    final Loan loan = _loan('a', 'Car loan');
    f.loans.add(loan);
    f.loanPayments.add(
      LoanPayment(
        id: 'p1',
        userId: 'u',
        loanId: 'a',
        accountId: 'acc-1',
        kind: LoanPaymentKind.scheduled,
        paidAt: DateTime(2027, 2, 5),
        amount: Decimal.parse('10379.18'),
        principalPart: Decimal.parse('6629.18'),
        interestPart: Decimal.parse('3750'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _start(tester, f);
    unawaited(
      Get.toNamed<void>(
        AppRoutes.loanForm,
        arguments: LoanFormArgs(existing: loan),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Terms are locked after the first payment'),
      findsOneWidget,
    );
    TextField field(String label) => tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, label),
        matching: find.byType(TextField),
      ),
    );
    expect(field('Principal').enabled, isFalse);
    expect(field('Interest rate (% a year)').enabled, isFalse);
    expect(field('Loan name').enabled, isTrue);

    // The pickers have no enabled flag: they are out of focus and touch.
    Finder lockedAround(Finder control) => find.ancestor(
      of: control,
      matching: find.byWidgetPredicate(
        (Widget w) => w is ExcludeFocus && w.excluding,
      ),
    );
    expect(lockedAround(find.text('Start date')), findsOneWidget);
    expect(lockedAround(find.text('First EMI date')), findsOneWidget);
    expect(lockedAround(find.text('Account')), findsOneWidget);
    expect(lockedAround(find.byType(Switch)), findsWidgets);
    expect(lockedAround(find.text('EMI').first), findsOneWidget);
    expect(lockedAround(find.text('Taken')), findsOneWidget);

    await tester.tap(find.byType(Switch), warnIfMissed: false);
    await tester.tap(find.text('Start date'), warnIfMissed: false);
    await tester.tap(find.text('Cash'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('an edit shows the skeleton first, then the filled fields', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
    final Loan loan = _loan('a', 'Car loan');
    f.loans.add(loan);
    await _start(tester, f);
    final Completer<void> gate = f.getLoanGate = Completer<void>();
    unawaited(
      Get.toNamed<void>(
        AppRoutes.loanForm,
        arguments: LoanFormArgs(existing: loan),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Loan name'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
    expect(find.text('Car loan'), findsOneWidget);
    expect(find.text('500000'), findsOneWidget);
    expect(find.text('10379.18'), findsOneWidget);
  });

  testWidgets('an edit that cannot load offers retry, not an editable form', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
    final Loan loan = _loan('a', 'Car loan');
    f.loans.add(loan);
    await _start(tester, f);
    f.failAll = const NetworkFailure();
    unawaited(
      Get.toNamed<void>(
        AppRoutes.loanForm,
        arguments: LoanFormArgs(existing: loan),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Loan name'), findsNothing);

    f.failAll = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Car loan'), findsOneWidget);
  });

  testWidgets('an edit whose account is not in the list still opens', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
    final Loan loan = _loan('a', 'Car loan', accountId: 'acc-gone');
    f.loans.add(loan);
    await _start(tester, f);
    unawaited(
      Get.toNamed<void>(
        AppRoutes.loanForm,
        arguments: LoanFormArgs(existing: loan),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Car loan'), findsOneWidget);
    expect(find.text('Cash'), findsNothing);
  });
}
