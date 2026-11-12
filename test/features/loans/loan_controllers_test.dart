import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:finance_tracker/features/loans/controllers/loan_form_controller.dart';
import 'package:finance_tracker/features/loans/controllers/loan_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime now = DateTime(2027, 1, 5, 12);

  Loan loan(
    String id, {
    LoanDirection direction = LoanDirection.taken,
    String principal = '500000',
    DateTime? closedAt,
  }) => Loan(
    id: id,
    userId: 'u',
    direction: direction,
    method: LoanMethod.emi,
    name: 'Loan $id',
    accountId: 'acc-1',
    principal: Decimal.parse(principal),
    annualRate: Decimal.parse('9'),
    tenureMonths: 60,
    emiAmount: Decimal.parse('10379.18'),
    startDate: DateTime(2027, 1, 5),
    firstDueDate: DateTime(2027, 2, 5),
    movedMoney: true,
    closedAt: closedAt,
    createdAt: now,
    updatedAt: now,
  );

  group('LoanListController', () {
    LoanListController build(FakeFinance f) {
      Get.testMode = true;
      addTearDown(Get.reset);
      return Get.put(
        LoanListController(f.repositories.loans, DataChangeNotifier()),
      );
    }

    test('filters by direction, sums open loans, keeps closed apart', () async {
      final FakeFinance f = FakeFinance();
      f.loans.addAll(<Loan>[
        loan('a'),
        loan('b', principal: '200000'),
        loan('c', closedAt: DateTime(2027, 6, 1)),
        loan('d', direction: LoanDirection.given, principal: '1000'),
      ]);
      final LoanListController c = build(f);
      await c.load();

      expect(c.direction.value, LoanDirection.taken);
      expect(c.open.map((s) => s.loan.id), <String>['a', 'b']);
      expect(c.closed.map((s) => s.loan.id), <String>['c']);
      expect(c.totalOutstanding, Decimal.parse('700000'));

      c.direction.value = LoanDirection.given;
      expect(c.open.map((s) => s.loan.id), <String>['d']);
      expect(c.closed, isEmpty);
      expect(c.totalOutstanding, Decimal.parse('1000'));
    });

    test('shows the load error', () async {
      final FakeFinance f = FakeFinance();
      final LoanListController c = build(f);
      await c.load();
      f.nextError = const NetworkFailure();
      await c.load();

      expect(c.error.value, isNotNull);
      expect(c.isLoading.value, isFalse);
    });

    test('reloads when the data changes', () async {
      final FakeFinance f = FakeFinance();
      final DataChangeNotifier notifier = DataChangeNotifier();
      Get.testMode = true;
      addTearDown(Get.reset);
      final LoanListController c = Get.put(
        LoanListController(f.repositories.loans, notifier),
      );
      await c.load();
      expect(c.loans, isEmpty);

      f.loans.add(loan('a'));
      notifier.markChanged();
      await Future<void>.delayed(Duration.zero);
      expect(c.loans, hasLength(1));
    });
  });

  group('LoanFormController', () {
    Future<LoanFormController> build(
      FakeFinance f, {
      LoanFormArgs args = const LoanFormArgs(),
    }) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      f.addAccount('Cash', '1000');
      final LoanFormController c = Get.put(
        LoanFormController(
          f.repositories.loans,
          f.repositories.accounts,
          f.repositories.contacts,
          DataChangeNotifier(),
        ),
      );
      await c.start(args);
      return c;
    }

    void typeSpecLoan(LoanFormController c) {
      c.name.value = 'HDFC Home Loan';
      c.principalText.value = '500000';
      c.rateText.value = '9';
      c.tenureText.value = '60';
    }

    test('starts on the first account, due a month after the start', () async {
      final FakeFinance f = FakeFinance();
      final LoanFormController c = await build(f);

      expect(c.accountId.value, 'acc-1');
      expect(c.direction.value, LoanDirection.taken);
      expect(
        c.firstDueDate.value,
        LoanCalculator.addMonths(c.startDate.value, 1),
      );
      expect(c.error, isNull);
    });

    test('the EMI follows principal, rate and tenure until edited', () async {
      final FakeFinance f = FakeFinance();
      final LoanFormController c = await build(f);
      typeSpecLoan(c);

      expect(c.suggestedEmi, Decimal.parse('10379.18'));
      expect(c.emiText.value, '10379.18');

      c.tenureText.value = '120';
      expect(c.emiText.value, '6333.79');

      c.editEmi('10400');
      c.tenureText.value = '60';
      expect(c.emiText.value, '10400');
    });

    test('the first due date follows the start date until picked', () async {
      final FakeFinance f = FakeFinance();
      final LoanFormController c = await build(f);

      c.startDate.value = DateTime(2027, 1, 31);
      expect(c.firstDueDate.value, DateTime(2027, 2, 28));

      c.firstDueDate.value = DateTime(2027, 3, 10);
      c.startDate.value = DateTime(2027, 1, 5);
      expect(c.firstDueDate.value, DateTime(2027, 3, 10));
    });

    test('preselects the first active account', () async {
      final FakeFinance f = FakeFinance();
      f.accounts.add(
        Account(
          id: 'acc-0',
          userId: 'u',
          name: 'Old',
          type: AccountType.bank,
          openingBalance: Decimal.zero,
          isActive: false,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final LoanFormController c = await build(f);

      expect(c.accountId.value, 'acc-1');
      expect(c.accounts.map((Account a) => a.id), <String>['acc-1']);
    });

    test(
      'an unlocked loan with the computed EMI refills on a change',
      () async {
        final FakeFinance f = FakeFinance();
        final Loan existing = loan('loan-1');
        f.loans.add(existing);
        final LoanFormController c = await build(
          f,
          args: LoanFormArgs(existing: existing),
        );
        expect(c.termsLocked.value, isFalse);
        expect(c.emiText.value, '10379.18');

        c.tenureText.value = '120';
        expect(c.emiText.value, '6333.79');
      },
    );

    test('a stored EMI that is not the computed one stays', () async {
      final FakeFinance f = FakeFinance();
      final Loan existing = loan(
        'loan-1',
      ).copyWith(emiAmount: Decimal.parse('10400'));
      f.loans.add(existing);
      final LoanFormController c = await build(
        f,
        args: LoanFormArgs(existing: existing),
      );
      expect(c.emiText.value, '10400');

      c.tenureText.value = '120';
      expect(c.emiText.value, '10400');
    });

    test('a monthly loan saves the rate times 12 and no EMI fields', () async {
      final FakeFinance f = FakeFinance();
      final LoanFormController c = await build(f);
      c.method.value = LoanMethod.monthlyInterest;
      c.name.value = 'Friend';
      c.principalText.value = '100000';
      c.rateText.value = '2';

      expect(c.error, isNull);
      expect(await c.saveLoan('loan-1'), isTrue);
      final Loan saved = f.loans.single;
      expect(saved.annualRate, Decimal.fromInt(24));
      expect(saved.tenureMonths, isNull);
      expect(saved.emiAmount, isNull);
      expect(saved.firstDueDate, isNull);
      expect(saved.method, LoanMethod.monthlyInterest);

      final LoanFormController edit = await build(
        f,
        args: LoanFormArgs(existing: saved),
      );
      expect(edit.rateText.value, '2');
    });

    test('an EMI below the first month interest is refused', () async {
      final FakeFinance f = FakeFinance();
      final LoanFormController c = await build(f);
      typeSpecLoan(c);
      c.editEmi('3000');

      expect(c.error, "The EMI does not cover the first month's interest");
      expect(await c.saveLoan('loan-1'), isFalse);
      expect(c.save.error.value, c.error);
      expect(f.loans, isEmpty);
    });

    test('stays quiet while principal or rate is blank', () async {
      final FakeFinance f = FakeFinance();
      final LoanFormController c = await build(f);
      c.name.value = 'x';
      c.principalText.value = '500000';
      expect(c.error, isNull);
      c.rateText.value = '90';
      expect(c.error, 'Interest rate must be between 0% and 60% a year');
    });

    test('saves the spec loan', () async {
      final FakeFinance f = FakeFinance();
      final LoanFormController c = await build(f);
      typeSpecLoan(c);
      c.startDate.value = DateTime(2027, 1, 5);

      expect(await c.saveLoan('loan-1'), isTrue);
      final Loan saved = f.loans.single;
      expect(saved.emiAmount, Decimal.parse('10379.18'));
      expect(saved.tenureMonths, 60);
      expect(saved.firstDueDate, DateTime(2027, 2, 5));
      expect(saved.accountId, 'acc-1');
    });

    test('after a payment only name, contact and note can change', () async {
      final FakeFinance f = FakeFinance();
      final Loan existing = loan('loan-1');
      f.loans.add(existing);
      f.loanPayments.add(
        LoanPayment(
          id: 'p1',
          userId: 'u',
          loanId: 'loan-1',
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
      final LoanFormController c = await build(
        f,
        args: LoanFormArgs(existing: existing),
      );

      expect(c.termsLocked.value, isTrue);
      expect(c.principalText.value, '500000');
      expect(c.emiText.value, '10379.18');

      c.principalText.value = '400000';
      expect(await c.saveLoan('loan-1'), isFalse);
      expect(
        c.save.error.value,
        'Only the name, contact and note can change after a payment',
      );

      c.principalText.value = '500000';
      c.name.value = 'Renamed';
      expect(await c.saveLoan('loan-1'), isTrue);
      expect(f.loans.single.name, 'Renamed');
      expect(f.loans.single.createdAt, existing.createdAt);
    });

    test('an edit keeps the closed date', () async {
      final FakeFinance f = FakeFinance();
      final Loan closed = loan('loan-1', closedAt: DateTime(2027, 6, 1));
      f.loans.add(closed);
      final LoanFormController c = await build(
        f,
        args: LoanFormArgs(existing: closed),
      );
      expect(c.termsLocked.value, isFalse);
      c.note.value = 'paid off';
      expect(await c.saveLoan('loan-1'), isTrue);
      expect(f.loans.single.closedAt, DateTime(2027, 6, 1));
      expect(f.loans.single.note, 'paid off');
    });
  });
}
