import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:finance_tracker/domain/services/loan_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Decimal d(String v) => Decimal.parse(v);

  Loan loan({
    String principal = '500000',
    String rate = '9',
    int months = 60,
    DateTime? start,
    DateTime? firstDue,
    String? emi,
  }) {
    final Decimal p = d(principal);
    final Decimal r = d(rate);
    return Loan(
      id: 'loan-1',
      userId: 'user-1',
      direction: LoanDirection.taken,
      method: LoanMethod.emi,
      name: 'Home loan',
      accountId: 'acc-1',
      principal: p,
      annualRate: r,
      tenureMonths: months,
      emiAmount: emi == null
          ? LoanCalculator.emi(principal: p, annualRate: r, months: months)
          : d(emi),
      startDate: start ?? DateTime(2027, 1, 5),
      firstDueDate: firstDue ?? DateTime(2027, 2, 5),
      movedMoney: true,
      createdAt: DateTime(2027, 1, 5),
      updatedAt: DateTime(2027, 1, 5),
    );
  }

  LoanPayment payment(
    String id,
    LoanPaymentKind kind,
    Decimal principal,
    Decimal interest, {
    DateTime? deletedAt,
  }) {
    return LoanPayment(
      id: id,
      userId: 'user-1',
      loanId: 'loan-1',
      accountId: 'acc-1',
      kind: kind,
      paidAt: DateTime(2027, 2, 5),
      amount: principal + interest,
      principalPart: principal,
      interestPart: interest,
      createdAt: DateTime(2027, 2, 5),
      updatedAt: DateTime(2027, 2, 5),
      deletedAt: deletedAt,
    );
  }

  List<LoanPayment> scheduledFrom(List<LoanInstalment> rows, int count) => [
    for (final LoanInstalment row in rows.take(count))
      payment(
        'p${row.number}',
        LoanPaymentKind.scheduled,
        row.principal,
        row.interest,
      ),
  ];

  group('emi and monthlyInterest', () {
    test('the spec loan: 5,00,000 at 9% over 60 months is 10379.18', () {
      expect(
        LoanCalculator.emi(
          principal: d('500000'),
          annualRate: d('9'),
          months: 60,
        ),
        d('10379.18'),
      );
    });

    test('a zero rate divides the principal evenly', () {
      expect(
        LoanCalculator.emi(principal: d('1000'), annualRate: d('0'), months: 3),
        d('333.33'),
      );
    });

    test('a half paisa rounds up', () {
      expect(LoanCalculator.monthlyInterest(d('0.5'), d('12')), d('0.01'));
    });
  });

  group('schedule', () {
    test('the spec loan with no payments has 60 rows', () {
      final Loan l = loan();
      final List<LoanInstalment> rows = LoanCalculator.schedule(l, const []);
      expect(rows, hasLength(60));
      expect(rows.first.number, 1);
      expect(rows.first.dueDate, DateTime(2027, 2, 5));
      expect(rows.first.interest, d('3750.00'));
      expect(rows.first.principal, d('6629.18'));
      expect(rows.first.amount, d('10379.18'));
      expect(rows.last.number, 60);
      expect(rows.last.principal, d('10301.71'));
      expect(rows.last.amount, d('10378.97'));
      expect(rows.last.balanceAfter, Decimal.zero);
      expect(
        rows.fold(
          Decimal.zero,
          (Decimal a, LoanInstalment r) => a + r.interest,
        ),
        d('122750.59'),
      );
    });

    test('after 12 EMIs and 1,00,000 prepaid, 35 EMIs remain', () {
      final Loan l = loan();
      final List<LoanInstalment> full = LoanCalculator.schedule(l, const []);
      final List<LoanPayment> payments = [
        ...scheduledFrom(full, 12),
        payment('x1', LoanPaymentKind.extra, d('100000'), Decimal.zero),
      ];
      expect(LoanCalculator.outstanding(l, payments), d('317084.97'));
      expect(LoanCalculator.instalmentsLeft(l, payments), 35);
      final List<LoanInstalment> rows = LoanCalculator.schedule(l, payments);
      expect(rows, hasLength(35));
      expect(rows.first.number, 13);
      expect(rows.first.dueDate, DateTime(2028, 2, 5));
      expect(rows.last.number, 47);
      expect(rows.last.amount, d('8592.08'));
      expect(rows.last.principal, d('8528.12'));
      expect(rows.last.interest, d('63.96'));
    });

    test('a zero rate loan ends 333.33, 333.33, 333.34', () {
      final Loan l = loan(principal: '1000', rate: '0', months: 3);
      expect(
        LoanCalculator.schedule(
          l,
          const [],
        ).map((LoanInstalment r) => r.amount),
        [d('333.33'), d('333.33'), d('333.34')],
      );
    });

    test('the tenure sets the row count, not the rounded EMI', () {
      final Loan l = loan(principal: '1631', rate: '10.5', months: 335);
      expect(LoanCalculator.schedule(l, const []), hasLength(335));
    });

    test('a closed loan has no schedule', () {
      final Loan l = loan().copyWith(closedAt: DateTime(2027, 3, 1));
      expect(LoanCalculator.schedule(l, const []), isEmpty);
    });

    test('a monthly interest loan has no schedule', () {
      final Loan l = Loan(
        id: 'loan-2',
        userId: 'user-1',
        direction: LoanDirection.given,
        method: LoanMethod.monthlyInterest,
        name: 'Friend',
        accountId: 'acc-1',
        principal: d('10000'),
        annualRate: d('24'),
        startDate: DateTime(2027, 1, 1),
        movedMoney: false,
        createdAt: DateTime(2027, 1, 1),
        updatedAt: DateTime(2027, 1, 1),
      );
      expect(LoanCalculator.schedule(l, const []), isEmpty);
      expect(LoanCalculator.instalmentsLeft(l, const []), 0);
    });
  });

  group('outstanding and instalmentsLeft', () {
    test('a deleted payment is ignored', () {
      final Loan l = loan();
      final List<LoanPayment> payments = [
        payment('a', LoanPaymentKind.scheduled, d('6629.18'), d('3750')),
        payment(
          'b',
          LoanPaymentKind.extra,
          d('100000'),
          Decimal.zero,
          deletedAt: DateTime(2027, 3, 1),
        ),
      ];
      expect(LoanCalculator.outstanding(l, payments), d('493370.82'));
      expect(LoanCalculator.instalmentsLeft(l, payments), 59);
    });

    test('nothing owed means nothing left', () {
      final Loan l = loan(principal: '1000', rate: '0', months: 3);
      final List<LoanPayment> payments = [
        payment('a', LoanPaymentKind.extra, d('1000'), Decimal.zero),
      ];
      expect(LoanCalculator.outstanding(l, payments), Decimal.zero);
      expect(LoanCalculator.instalmentsLeft(l, payments), 0);
      expect(LoanCalculator.schedule(l, payments), isEmpty);
    });

    test(
      'a zero rate count after a prepayment is exact, not a double ceil',
      () {
        // 5.70 / 1.14 is 5.000000000000001 in doubles, which would give 6.
        final Loan l = loan(
          principal: '11.40',
          rate: '0',
          months: 10,
          emi: '1.14',
        );
        final List<LoanPayment> payments = [
          payment('x', LoanPaymentKind.extra, d('5.70'), Decimal.zero),
        ];
        expect(LoanCalculator.outstanding(l, payments), d('5.70'));
        expect(LoanCalculator.instalmentsLeft(l, payments), 5);
        expect(
          LoanCalculator.schedule(l, payments),
          hasLength(LoanCalculator.instalmentsLeft(l, payments)),
        );
      },
    );

    test('at least one EMI is left while something is owed', () {
      final Loan l = loan(principal: '1000', rate: '0', months: 2);
      final List<LoanPayment> payments = [
        payment('a', LoanPaymentKind.scheduled, d('400'), Decimal.zero),
        payment('b', LoanPaymentKind.scheduled, d('400'), Decimal.zero),
      ];
      expect(LoanCalculator.instalmentsLeft(l, payments), 1);
      final List<LoanInstalment> rows = LoanCalculator.schedule(l, payments);
      expect(rows, hasLength(1));
      expect(rows.single.number, 3);
      expect(rows.single.amount, d('200'));
    });
  });

  group('dates', () {
    test('addMonths clamps the day to the target month', () {
      expect(
        LoanCalculator.addMonths(DateTime(2027, 1, 31), 1),
        DateTime(2027, 2, 28),
      );
      expect(
        LoanCalculator.addMonths(DateTime(2027, 1, 31), 2),
        DateTime(2027, 3, 31),
      );
      expect(
        LoanCalculator.addMonths(DateTime(2028, 1, 31), 1),
        DateTime(2028, 2, 29),
      );
    });

    test('dueDate counts from the first due date', () {
      final Loan l = loan(firstDue: DateTime(2027, 1, 31));
      expect(LoanCalculator.dueDate(l, 1), DateTime(2027, 1, 31));
      expect(LoanCalculator.dueDate(l, 3), DateTime(2027, 3, 31));
    });
  });

  group('LoanIds', () {
    test('the same input gives the same id', () {
      expect(LoanIds.loanRow('a'), LoanIds.loanRow('a'));
      expect(LoanIds.reminder('a'), LoanIds.reminder('a'));
    });

    test('different inputs give different ids', () {
      expect(LoanIds.loanRow('a'), isNot(LoanIds.loanRow('b')));
      expect(LoanIds.loanRow('a'), isNot(LoanIds.reminder('a')));
    });

    test('a payment principal and interest row differ', () {
      expect(
        LoanIds.paymentPrincipal('x'),
        isNot(LoanIds.paymentInterest('x')),
      );
    });
  });
}
