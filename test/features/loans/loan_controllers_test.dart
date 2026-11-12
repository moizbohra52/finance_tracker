import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:finance_tracker/features/loans/controllers/loan_detail_controller.dart';
import 'package:finance_tracker/features/loans/controllers/loan_form_controller.dart';
import 'package:finance_tracker/features/loans/controllers/loan_list_controller.dart';
import 'package:finance_tracker/features/loans/controllers/loan_payment_controller.dart';
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

    test('progress is the principal repaid over the principal', () async {
      final FakeFinance f = FakeFinance();
      f.loans.add(loan('a', principal: '1000'));
      f.loanPayments.add(
        LoanPayment(
          id: 'p1',
          userId: 'u',
          loanId: 'a',
          accountId: 'acc-1',
          kind: LoanPaymentKind.scheduled,
          paidAt: DateTime(2027, 2, 5),
          amount: Decimal.parse('300'),
          principalPart: Decimal.parse('250'),
          interestPart: Decimal.parse('50'),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final LoanListController c = build(f);
      await c.load();

      expect(c.progressOf(c.loans.single), 0.25);
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
      f.accounts.insert(
        0,
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

  LoanPayment payment(
    String id,
    DateTime paidAt, {
    String amount = '10379.18',
    String principal = '6629.18',
    String interest = '3750',
  }) => LoanPayment(
    id: id,
    userId: 'u',
    loanId: 'loan-1',
    accountId: 'acc-1',
    kind: LoanPaymentKind.scheduled,
    paidAt: paidAt,
    amount: Decimal.parse(amount),
    principalPart: Decimal.parse(principal),
    interestPart: Decimal.parse(interest),
    createdAt: now,
    updatedAt: now,
  );

  Loan ravi() => Loan(
    id: 'ravi',
    userId: 'u',
    direction: LoanDirection.given,
    method: LoanMethod.monthlyInterest,
    name: 'Ravi',
    accountId: 'acc-1',
    principal: Decimal.parse('10000'),
    annualRate: Decimal.parse('24'),
    startDate: DateTime(2027, 1, 1),
    movedMoney: true,
    createdAt: now,
    updatedAt: now,
  );

  group('LoanDetailController', () {
    LoanDetailController build(FakeFinance f, DataChangeNotifier n) {
      Get.testMode = true;
      addTearDown(Get.reset);
      return Get.put(LoanDetailController(f.repositories.loans, n, 'loan-1'));
    }

    test('loads the schedule; only the latest payment can change', () async {
      final FakeFinance f = FakeFinance();
      f.loans.add(loan('loan-1'));
      final LoanDetailController c = build(f, DataChangeNotifier());
      await c.load();
      expect(c.schedule, hasLength(60));
      expect(c.isLoading.value, isFalse);

      final LoanPayment older = payment('p1', DateTime(2027, 2, 5));
      final LoanPayment newer = payment(
        'p2',
        DateTime(2027, 3, 5),
        principal: '6663.77',
        interest: '3715.41',
      );
      f.loanPayments.addAll(<LoanPayment>[older, newer]);
      await c.load();
      expect(c.schedule, hasLength(58));
      expect(c.canChange(newer), isTrue);
      expect(c.canChange(older), isFalse);

      expect(await c.deletePayment('p1'), isFalse);
      expect(c.deletion.error.value, 'Only the latest payment can be changed');
      expect(await c.deletePayment('p2'), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(c.detail.value!.payments.map((LoanPayment p) => p.id), <String>[
        'p1',
      ]);
    });

    test(
      'reloads on the notifier; deleting the loan marks the change',
      () async {
        final FakeFinance f = FakeFinance();
        f.loans.add(loan('loan-1'));
        final DataChangeNotifier n = DataChangeNotifier();
        final LoanDetailController c = build(f, n);
        await c.load();
        f.loanPayments.add(payment('p1', DateTime(2027, 2, 5)));
        n.markChanged();
        await Future<void>.delayed(Duration.zero);
        expect(c.detail.value!.payments, hasLength(1));

        final int version = n.version.value;
        expect(await c.deleteLoan(), isTrue);
        expect(n.version.value, greaterThan(version));
        expect(f.loans.single.isLive, isFalse);
      },
    );

    test('shows the load error', () async {
      final FakeFinance f = FakeFinance();
      final LoanDetailController c = build(f, DataChangeNotifier());
      await c.load();
      expect(c.error.value, isNotNull);
      expect(c.detail.value, isNull);
    });
  });

  group('LoanPaymentController', () {
    Future<LoanPaymentController> build(
      FakeFinance f,
      Object? args, {
      DataChangeNotifier? notifier,
    }) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      f.addAccount('Cash', '1000');
      final LoanPaymentController c = Get.put(
        LoanPaymentController(
          f.repositories.loans,
          f.repositories.accounts,
          notifier ?? DataChangeNotifier(),
        ),
      );
      await c.start(LoanPaymentArgs.of(args));
      return c;
    }

    test('args accept a bare id or an object, nothing else', () {
      expect(LoanPaymentArgs.of('loan-1').loanId, 'loan-1');
      expect(LoanPaymentArgs.of('loan-1').kind, LoanPaymentKind.scheduled);
      const LoanPaymentArgs a = LoanPaymentArgs(loanId: 'x', closing: true);
      expect(LoanPaymentArgs.of(a), same(a));
      expect(() => LoanPaymentArgs.of(3), throwsArgumentError);
      expect(() => LoanPaymentArgs.of(null), throwsArgumentError);
    });

    test('prefills the next EMI and re-splits what is typed', () async {
      final FakeFinance f = FakeFinance();
      f.loans.add(loan('loan-1'));
      final LoanPaymentController c = await build(f, 'loan-1');

      c.setDate(DateTime(2027, 2, 5));
      expect(c.accountId.value, 'acc-1');
      expect(c.amountText.value, '10379.18');
      expect(c.principalText.value, '6629.18');
      expect(c.interestText.value, '3750.00');
      expect(c.error, isNull);

      c.setAmount('12000');
      expect(c.principalText.value, '8250.00');
      expect(c.interestText.value, '3750.00');

      c.setInterest('3000');
      expect(c.principalText.value, '9000.00');
      c.setPrincipal('8000');
      expect(c.interestText.value, '4000.00');
    });

    test('saves, notifies and a retry upserts one payment', () async {
      final FakeFinance f = FakeFinance();
      f.loans.add(loan('loan-1'));
      final DataChangeNotifier n = DataChangeNotifier();
      final LoanPaymentController c = await build(f, 'loan-1', notifier: n);
      c.setDate(DateTime(2027, 2, 5));
      c.note.value = ' first ';
      final int version = n.version.value;

      expect(await c.savePayment(), isTrue);
      expect(await c.savePayment(), isTrue);
      expect(n.version.value, greaterThan(version));
      expect(f.loanPayments, hasLength(1));
      expect(f.loanPayments.single.note, 'first');
      expect(f.loanPayments.single.kind, LoanPaymentKind.scheduled);
      expect(f.loanPayments.single.paidAt, DateTime(2027, 2, 5));
    });

    test(
      'a back-dated payment shows the date message and is refused',
      () async {
        final FakeFinance f = FakeFinance();
        f.loans.add(loan('loan-1'));
        f.loanPayments.add(payment('p1', DateTime(2027, 3, 5)));
        final LoanPaymentController c = await build(f, 'loan-1');

        c.setDate(DateTime(2027, 2, 10));
        expect(
          c.error,
          'A payment cannot be dated before the previous one or the loan start',
        );
        expect(await c.savePayment(), isFalse);
        expect(c.save.error.value, c.error);
        expect(f.loanPayments, hasLength(1));
      },
    );

    test('a monthly loan prefills the unpaid interest', () async {
      final FakeFinance f = FakeFinance();
      f.loans.add(ravi());
      final LoanPaymentController c = await build(f, 'ravi');
      c.setDate(DateTime(2027, 3, 15));
      expect(c.amountText.value, '400.00');
      expect(c.principalText.value, '0.00');
      expect(c.interestText.value, '400.00');

      c.setAmount('3000');
      expect(c.principalText.value, '2600.00');
      expect(c.interestText.value, '400.00');
      expect(c.error, isNull);
    });

    test('closing prefills the payoff; kind follows the loan method', () async {
      final FakeFinance f = FakeFinance();
      f.loans.add(ravi());
      final LoanPaymentController c = await build(
        f,
        const LoanPaymentArgs(
          loanId: 'ravi',
          kind: LoanPaymentKind.extra,
          closing: true,
        ),
      );
      c.setDate(DateTime(2027, 3, 15));
      expect(c.amountText.value, '10400.00');
      expect(c.kind, LoanPaymentKind.scheduled);
      expect(await c.savePayment(), isTrue);
      expect(f.loans.single.isClosed, isTrue);
    });

    test(
      'closing an EMI loan is an extra payment of the outstanding',
      () async {
        final FakeFinance g = FakeFinance();
        g.loans.add(loan('loan-1'));
        final LoanPaymentController e = await build(
          g,
          const LoanPaymentArgs(
            loanId: 'loan-1',
            kind: LoanPaymentKind.extra,
            closing: true,
          ),
        );
        expect(e.kind, LoanPaymentKind.extra);
        expect(e.amountText.value, '500000.00');
        expect(e.interestText.value, '0.00');
      },
    );

    test(
      'an edit prefills the payment and checks the other payments',
      () async {
        final FakeFinance f = FakeFinance();
        f.loans.add(loan('loan-1'));
        final LoanPayment p1 = payment('p1', DateTime(2027, 2, 5));
        final LoanPayment p2 = payment(
          'p2',
          DateTime(2027, 3, 5),
          principal: '6663.77',
          interest: '3715.41',
        );
        f.loanPayments.addAll(<LoanPayment>[p1, p2]);
        final LoanPaymentController c = await build(
          f,
          LoanPaymentArgs(loanId: 'loan-1', existing: p2),
        );
        expect(c.amountText.value, '10379.18');
        expect(c.principalText.value, '6663.77');
        expect(c.paidAt.value, DateTime(2027, 3, 5));

        c.setDate(DateTime(2027, 2, 1));
        expect(c.error, isNotNull);
        c.setDate(DateTime(2027, 3, 6));
        c.setAmount('11000');
        expect(c.error, isNull);
        expect(await c.savePayment(), isTrue);
        expect(f.loanPayments, hasLength(2));
        expect(
          f.loanPayments.firstWhere((LoanPayment p) => p.id == 'p2').amount,
          Decimal.parse('11000'),
        );
      },
    );

    test(
      'editing a monthly payment keeps its amount when the date moves',
      () async {
        final FakeFinance f = FakeFinance();
        f.loans.add(ravi());
        final LoanPayment saved = LoanPayment(
          id: 'r1',
          userId: 'u',
          loanId: 'ravi',
          accountId: 'acc-1',
          kind: LoanPaymentKind.scheduled,
          paidAt: DateTime(2027, 3, 15),
          amount: Decimal.parse('3000'),
          principalPart: Decimal.parse('2600'),
          interestPart: Decimal.parse('400'),
          createdAt: now,
          updatedAt: now,
        );
        f.loanPayments.add(saved);
        final LoanPaymentController c = await build(
          f,
          LoanPaymentArgs(loanId: 'ravi', existing: saved),
        );

        c.setDate(DateTime(2027, 3, 20));
        expect(c.amountText.value, '3000.00');
        expect(c.principalText.value, '2600.00');
        expect(c.interestText.value, '400.00');
        expect(c.error, isNull);

        c.setAmount('');
        c.setDate(DateTime(2027, 3, 21));
        expect(c.amountText.value, '');
        expect(c.principalText.value, '2600.00');
      },
    );

    test('text that is not a number is refused, not read as zero', () async {
      final FakeFinance f = FakeFinance();
      f.loans.add(loan('loan-1'));
      final LoanPaymentController c = await build(f, 'loan-1');
      c.setDate(DateTime(2027, 2, 5));
      c.setAmount('5000');
      c.setInterest('5000');
      c.principalText.value = 'abc';

      expect(c.error, 'Enter a valid number');
      expect(await c.savePayment(), isFalse);
      expect(c.save.error.value, 'Enter a valid number');
      expect(f.loanPayments, isEmpty);

      c.setAmount('1,200');
      expect(c.error, 'Enter a valid number');
      expect(await c.savePayment(), isFalse);
      expect(f.loanPayments, isEmpty);
    });

    test('a future start date sets the default date', () async {
      final FakeFinance f = FakeFinance();
      f.loans.add(
        loan('loan-1').copyWith(
          startDate: DateTime(2099, 1, 5),
          firstDueDate: DateTime(2099, 2, 5),
        ),
      );
      final LoanPaymentController c = await build(f, 'loan-1');
      expect(c.paidAt.value, DateTime(2099, 1, 5));
      expect(c.error, isNull);
    });

    test('a future-dated last payment sets the default date', () async {
      final FakeFinance f = FakeFinance();
      f.loans.add(loan('loan-1'));
      f.loanPayments.add(payment('p1', DateTime(2099, 3, 5)));
      final LoanPaymentController c = await build(f, 'loan-1');
      expect(c.paidAt.value, DateTime(2099, 3, 5));
      expect(c.error, isNull);
    });

    test('a missing loan sets loadError and cannot be saved', () async {
      final FakeFinance f = FakeFinance();
      final LoanPaymentController c = await build(f, 'nope');
      expect(c.loadError.value, isNotNull);
      expect(c.loan.value, isNull);
      expect(await c.savePayment(), isFalse);
    });

    test(
      'an inactive loan account falls back to the first active one',
      () async {
        final FakeFinance f = FakeFinance();
        f.loans.add(loan('loan-1').copyWith(accountId: 'gone'));
        final LoanPaymentController c = await build(f, 'loan-1');
        expect(c.accountId.value, 'acc-1');
      },
    );
  });
}
