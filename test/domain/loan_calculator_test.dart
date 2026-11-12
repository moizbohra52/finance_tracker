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
    DateTime? paidAt,
    DateTime? deletedAt,
  }) {
    return LoanPayment(
      id: id,
      userId: 'user-1',
      loanId: 'loan-1',
      accountId: 'acc-1',
      kind: kind,
      paidAt: paidAt ?? DateTime(2027, 2, 5),
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

  // Ravi owes the user 10,000 at 2% a month (annualRate 24) from 1 Jan 2027.
  Loan monthly({String principal = '10000', DateTime? start}) => Loan(
    id: 'loan-1',
    userId: 'user-1',
    direction: LoanDirection.given,
    method: LoanMethod.monthlyInterest,
    name: 'Ravi',
    accountId: 'acc-1',
    principal: d(principal),
    annualRate: d('24'),
    startDate: start ?? DateTime(2027, 1, 1),
    movedMoney: false,
    createdAt: DateTime(2027, 1, 1),
    updatedAt: DateTime(2027, 1, 1),
  );

  // A payment on a given day; monthly-interest payments use the scheduled kind.
  LoanPayment paid(
    String principal,
    String interest,
    DateTime paidAt, {
    LoanPaymentKind kind = LoanPaymentKind.scheduled,
    DateTime? deletedAt,
  }) => payment(
    'pay-${paidAt.millisecondsSinceEpoch}',
    kind,
    d(principal),
    d(interest),
    paidAt: paidAt,
    deletedAt: deletedAt,
  );

  // Every field a message can depend on; the defaults make a valid EMI loan.
  Loan raw({
    LoanMethod method = LoanMethod.emi,
    String name = 'Home loan',
    String accountId = 'acc-1',
    String principal = '500000',
    String rate = '9',
    int? tenure = 60,
    String? emi = '10379.18',
    bool withFirstDue = true,
    DateTime? firstDue,
  }) => Loan(
    id: 'loan-1',
    userId: 'user-1',
    direction: LoanDirection.taken,
    method: method,
    name: name,
    accountId: accountId,
    principal: d(principal),
    annualRate: d(rate),
    tenureMonths: tenure,
    emiAmount: emi == null ? null : d(emi),
    startDate: DateTime(2027, 1, 5),
    firstDueDate: withFirstDue ? (firstDue ?? DateTime(2027, 2, 5)) : null,
    movedMoney: true,
    createdAt: DateTime(2027, 1, 5),
    updatedAt: DateTime(2027, 1, 5),
  );

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

  group('monthly interest (Ravi, 10,000 at 2% a month from 1 Jan 2027)', () {
    final Loan ravi = monthly();
    final LoanPayment march = paid('2600', '400', DateTime(2027, 3, 15));

    test('two months are complete on 15 Mar: 400 accrued', () {
      expect(
        LoanCalculator.accruedInterest(ravi, const [], DateTime(2027, 3, 15)),
        d('400'),
      );
      expect(
        LoanCalculator.accruedInterest(ravi, const [], DateTime(2027, 1, 31)),
        Decimal.zero,
      );
    });

    test('an EMI loan accrues nothing', () {
      expect(
        LoanCalculator.accruedInterest(loan(), const [], DateTime(2028, 1, 1)),
        Decimal.zero,
      );
    });

    test('3,000 on 15 Mar is 400 interest and 2,600 principal', () {
      final LoanPart part = LoanCalculator.suggest(
        ravi,
        const [],
        kind: LoanPaymentKind.scheduled,
        paidAt: DateTime(2027, 3, 15),
        amount: d('3000'),
      );
      expect(part.interest, d('400'));
      expect(part.principal, d('2600'));
      expect(part.amount, d('3000'));
    });

    test(
      'a small amount is all interest; no amount is the unpaid interest',
      () {
        final LoanPart small = LoanCalculator.suggest(
          ravi,
          const [],
          kind: LoanPaymentKind.scheduled,
          paidAt: DateTime(2027, 3, 15),
          amount: d('100'),
        );
        expect(small.interest, d('100'));
        expect(small.principal, Decimal.zero);
        final LoanPart none = LoanCalculator.suggest(
          ravi,
          const [],
          kind: LoanPaymentKind.scheduled,
          paidAt: DateTime(2027, 3, 15),
        );
        expect(none.amount, d('400'));
        expect(none.interest, d('400'));
        expect(none.principal, Decimal.zero);
      },
    );

    test('after that payment 7,400 is owed and April starts on 7,400', () {
      final List<LoanPayment> payments = [march];
      expect(LoanCalculator.outstanding(ravi, payments), d('7400'));
      expect(LoanCalculator.nextDueDate(ravi, payments), DateTime(2027, 4, 1));
      final LoanStatus status = LoanCalculator.status(ravi, payments);
      // March's month started on 1 Mar, when 10,000 was still owed.
      expect(status.nextAmount, d('200.00'));
      expect(status.outstanding, d('7400'));
      expect(status.principalRepaid, d('2600'));
      expect(status.interestPaid, d('400'));
      expect(status.instalmentsLeft, isNull);
      expect(
        LoanCalculator.unpaidInterest(ravi, payments, DateTime(2027, 5, 1)),
        d('348.00'),
      );
    });

    test(
      'unpaid interest is never below zero and ignores deleted payments',
      () {
        expect(
          LoanCalculator.unpaidInterest(ravi, [
            paid('0', '500', DateTime(2027, 3, 15)),
          ], DateTime(2027, 3, 15)),
          Decimal.zero,
        );
        final LoanPayment gone = paid(
          '2600',
          '400',
          DateTime(2027, 3, 15),
          deletedAt: DateTime(2027, 3, 16),
        );
        expect(
          LoanCalculator.accruedInterest(ravi, [gone], DateTime(2027, 5, 1)),
          d('800'),
        );
        expect(LoanCalculator.nextDueDate(ravi, [gone]), DateTime(2027, 2, 1));
      },
    );

    test('interest paid in advance leaves no next amount, not 0', () {
      final List<LoanPayment> payments = [
        paid('0', '600', DateTime(2027, 3, 15)),
      ];
      final LoanStatus status = LoanCalculator.status(ravi, payments);
      expect(status.nextDueDate, DateTime(2027, 4, 1));
      expect(status.nextAmount, isNull);
      expect(LoanCalculator.status(ravi, [march]).nextAmount, d('200.00'));
    });

    test('an interest-free monthly loan has no next amount', () {
      final LoanStatus status = LoanCalculator.status(
        ravi.copyWith(annualRate: Decimal.zero),
        const [],
      );
      expect(status.nextDueDate, DateTime(2027, 2, 1));
      expect(status.nextAmount, isNull);
    });

    test('closing on 15 Mar is 10,400: 400 interest, 10,000 principal', () {
      final LoanPart part = LoanCalculator.suggest(
        ravi,
        const [],
        kind: LoanPaymentKind.scheduled,
        paidAt: DateTime(2027, 3, 15),
        closing: true,
      );
      expect(part.amount, d('10400'));
      expect(part.interest, d('400'));
      expect(part.principal, d('10000'));
    });

    test('a closed loan has no next due date', () {
      expect(
        LoanCalculator.nextDueDate(
          ravi.copyWith(closedAt: DateTime(2027, 3, 15)),
          [march],
        ),
        isNull,
      );
    });
  });

  group('monthly interest across short months', () {
    // 1,000 at 24% from 31 Jan 2027: 20 a month, anniversaries 28 Feb,
    // 31 Mar, 30 Apr.
    final Loan l = monthly(principal: '1000', start: DateTime(2027, 1, 31));

    test('a month completes on the clamped anniversary', () {
      Decimal accrued(DateTime on) =>
          LoanCalculator.accruedInterest(l, const [], on);
      expect(accrued(DateTime(2027, 2, 27)), Decimal.zero);
      expect(accrued(DateTime(2027, 2, 28)), d('20'));
      expect(accrued(DateTime(2027, 3, 31)), d('40'));
      expect(accrued(DateTime(2027, 4, 30)), d('60'));
    });

    test('20 on 28 Feb is all interest and the next due date is 31 Mar', () {
      final LoanPart part = LoanCalculator.suggest(
        l,
        const [],
        kind: LoanPaymentKind.scheduled,
        paidAt: DateTime(2027, 2, 28),
        amount: d('20'),
      );
      expect(part.interest, d('20'));
      expect(part.principal, Decimal.zero);
      expect(
        LoanCalculator.nextDueDate(l, [paid('0', '20', DateTime(2027, 2, 28))]),
        DateTime(2027, 3, 31),
      );
    });
  });

  group('suggest, nextDueDate and status for an EMI loan', () {
    final Loan l = loan();
    final List<LoanInstalment> full = LoanCalculator.schedule(l, const []);
    final List<LoanPayment> twelve = scheduledFrom(full, 12);

    test('the next EMI of a new loan is 10379.18: 6629.18 and 3750.00', () {
      final LoanPart part = LoanCalculator.suggest(
        l,
        const [],
        kind: LoanPaymentKind.scheduled,
        paidAt: DateTime(2027, 2, 5),
      );
      expect(part.amount, d('10379.18'));
      expect(part.principal, d('6629.18'));
      expect(part.interest, d('3750.00'));
    });

    test('a typed amount covers interest first', () {
      final LoanPart low = LoanCalculator.suggest(
        l,
        const [],
        kind: LoanPaymentKind.scheduled,
        paidAt: DateTime(2027, 2, 5),
        amount: d('3000'),
      );
      expect(low.interest, d('3000'));
      expect(low.principal, Decimal.zero);
      final LoanPart high = LoanCalculator.suggest(
        l,
        const [],
        kind: LoanPaymentKind.scheduled,
        paidAt: DateTime(2027, 2, 5),
        amount: d('5000'),
      );
      expect(high.interest, d('3750.00'));
      expect(high.principal, d('1250.00'));
    });

    test('an extra payment is all principal', () {
      final LoanPart part = LoanCalculator.suggest(
        l,
        twelve,
        kind: LoanPaymentKind.extra,
        paidAt: DateTime(2028, 2, 10),
        amount: d('100000'),
      );
      expect(part.principal, d('100000'));
      expect(part.interest, Decimal.zero);
    });

    test('closing after 12 EMIs is the 417084.97 still owed, no interest', () {
      final LoanPart part = LoanCalculator.suggest(
        l,
        twelve,
        kind: LoanPaymentKind.extra,
        paidAt: DateTime(2028, 2, 10),
        closing: true,
      );
      expect(part.amount, d('417084.97'));
      expect(part.principal, d('417084.97'));
      expect(part.interest, Decimal.zero);
    });

    test('after 12 EMIs and a prepayment the next due date is the 13th', () {
      final List<LoanPayment> payments = [
        ...twelve,
        payment('x1', LoanPaymentKind.extra, d('100000'), Decimal.zero),
      ];
      expect(
        LoanCalculator.nextDueDate(l, payments),
        LoanCalculator.dueDate(l, 13),
      );
      final LoanStatus status = LoanCalculator.status(l, payments);
      expect(status.instalmentsLeft, 35);
      expect(status.outstanding, d('317084.97'));
      expect(status.nextDueDate, DateTime(2028, 2, 5));
      expect(
        status.nextAmount,
        LoanCalculator.schedule(l, payments).first.amount,
      );
    });

    test('deleted payments and a closed loan', () {
      final LoanPayment gone = payment(
        'g',
        LoanPaymentKind.scheduled,
        d('6629.18'),
        d('3750'),
        deletedAt: DateTime(2027, 3, 1),
      );
      expect(LoanCalculator.nextDueDate(l, [gone]), DateTime(2027, 2, 5));
      expect(
        LoanCalculator.nextDueDate(
          l.copyWith(closedAt: DateTime(2027, 3, 1)),
          const [],
        ),
        isNull,
      );
    });
  });

  group('validateLoan', () {
    String? check(Loan l) => LoanCalculator.validateLoan(l);

    test('the spec loan, a zero-rate EMI loan and Ravi are valid', () {
      expect(check(loan()), isNull);
      expect(check(loan(principal: '1000', rate: '0', months: 3)), isNull);
      expect(check(monthly()), isNull);
    });

    test('each message, in order', () {
      expect(check(raw(name: '  ')), 'Give the loan a name');
      expect(check(raw(accountId: '')), 'Choose an account');
      expect(check(raw(principal: '0')), 'Amount must be more than zero');
      expect(check(raw(principal: '-5')), 'Amount must be more than zero');
      expect(
        check(raw(principal: '100.001')),
        'Amounts can have at most 2 decimals',
      );
      expect(
        check(raw(emi: '10379.181')),
        'Amounts can have at most 2 decimals',
      );
      expect(
        check(raw(rate: '60.01')),
        'Interest rate must be between 0% and 60% a year',
      );
      expect(
        check(raw(rate: '-1')),
        'Interest rate must be between 0% and 60% a year',
      );
      expect(
        check(monthly().copyWith(annualRate: d('61'))),
        'Interest rate must be between 0% and 5% a month',
      );
      expect(check(raw(tenure: 0)), 'Tenure must be 1 to 480 months');
      expect(check(raw(tenure: 481)), 'Tenure must be 1 to 480 months');
      expect(check(raw(tenure: null)), 'Tenure must be 1 to 480 months');
      expect(check(raw(emi: null)), 'Enter the EMI');
      expect(check(raw(emi: '0')), 'Enter the EMI');
      expect(
        check(raw(emi: '3750.00')),
        "The EMI does not cover the first month's interest",
      );
      expect(check(raw(withFirstDue: false)), 'Choose the first EMI date');
      expect(
        check(raw(firstDue: DateTime(2027, 1, 4))),
        'The first EMI cannot be before the loan starts',
      );
    });

    test('the name is at most 80 characters, after the blank check', () {
      expect(check(raw(name: 'a' * 80)), isNull);
      expect(check(raw(name: 'a' * 81)), 'Keep the name to 80 characters');
      expect(check(raw(name: '${' ' * 5}${'a' * 80}${' ' * 5}')), isNull);
      expect(
        check(raw(name: 'a' * 81, accountId: '')),
        'Keep the name to 80 characters',
      );
    });

    test('the rate has at most 4 decimals, after the range check', () {
      expect(check(raw(rate: '9.5')), isNull);
      expect(check(raw(rate: '9.1234')), isNull);
      expect(
        check(raw(rate: '9.12345')),
        'Interest rate can have at most 4 decimals',
      );
      expect(
        check(raw(rate: '60.00001')),
        'Interest rate must be between 0% and 60% a year',
      );
    });

    test('the limits themselves are allowed', () {
      expect(check(loan(rate: '60')), isNull);
      expect(check(monthly().copyWith(annualRate: d('60'))), isNull);
      expect(check(loan(months: 1)), isNull);
      expect(check(loan(months: 480)), isNull);
      expect(check(raw(firstDue: DateTime(2027, 1, 5))), isNull);
    });

    test('an earlier message wins', () {
      expect(
        check(raw(name: '', principal: '0', rate: '70')),
        'Give the loan a name',
      );
      expect(
        check(raw(principal: '0', rate: '70')),
        'Amount must be more than zero',
      );
      expect(
        check(raw(tenure: 0, emi: null, withFirstDue: false)),
        'Tenure must be 1 to 480 months',
      );
    });
  });

  group('validatePayment', () {
    final Loan l = loan();
    final List<LoanInstalment> full = LoanCalculator.schedule(l, const []);
    final List<LoanPayment> twelve = scheduledFrom(full, 12);
    final Loan ravi = monthly();
    final LoanPayment march = paid('2600', '400', DateTime(2027, 3, 15));

    String? check(Loan loan, List<LoanPayment> earlier, LoanPayment p) =>
        LoanCalculator.validatePayment(loan, earlier, p);

    LoanPayment at(
      DateTime when, {
      String principal = '100',
      String interest = '0',
      LoanPaymentKind kind = LoanPaymentKind.scheduled,
    }) => paid(principal, interest, when, kind: kind);

    test('the amount must be more than zero', () {
      expect(
        check(l, const [], at(DateTime(2027, 2, 5), principal: '0')),
        'Amount must be more than zero',
      );
    });

    test('at most 2 decimals', () {
      expect(
        check(l, const [], at(DateTime(2027, 2, 5), principal: '100.005')),
        'Amounts can have at most 2 decimals',
      );
    });

    test('the parts must add up to the amount, and none is negative', () {
      final LoanPayment off = at(
        DateTime(2027, 2, 5),
        principal: '100',
        interest: '50',
      ).copyWith(amount: d('200'));
      expect(
        check(l, const [], off),
        'Principal and interest must add up to the amount',
      );
      final LoanPayment negative = at(
        DateTime(2027, 2, 5),
        principal: '150',
        interest: '-50',
      );
      expect(
        check(l, const [], negative),
        'Principal and interest must add up to the amount',
      );
    });

    test('a payment cannot be back-dated', () {
      const String message =
          'A payment cannot be dated before the previous one or the loan start';
      expect(check(ravi, [march], at(DateTime(2027, 3, 14))), message);
      expect(check(l, const [], at(DateTime(2027, 1, 4))), message);
      expect(check(ravi, const [], at(DateTime(2026, 12, 31))), message);
    });

    test('the same day as the previous payment or the start is allowed', () {
      expect(check(ravi, [march], at(DateTime(2027, 3, 15))), isNull);
      expect(
        check(ravi, [
          paid('2600', '400', DateTime(2027, 3, 15, 18)),
        ], at(DateTime(2027, 3, 15, 9))),
        isNull,
      );
      expect(check(l, const [], at(DateTime(2027, 1, 5))), isNull);
    });

    test('a deleted payment does not block an earlier date', () {
      final LoanPayment gone = paid(
        '100',
        '0',
        DateTime(2027, 6, 1),
        deletedAt: DateTime(2027, 6, 2),
      );
      expect(check(ravi, [march, gone], at(DateTime(2027, 3, 16))), isNull);
    });

    test('a repaid loan takes no more payments', () {
      expect(
        check(ravi, [
          paid('10000', '0', DateTime(2027, 3, 15)),
        ], at(DateTime(2027, 3, 16))),
        'This loan is already repaid',
      );
    });

    test('the principal part cannot pass what is still owed', () {
      expect(
        check(
          l,
          twelve,
          at(
            DateTime(2028, 2, 10),
            principal: '417084.98',
            kind: LoanPaymentKind.extra,
          ),
        ),
        'This is more than the principal still owed',
      );
      expect(
        check(
          l,
          twelve,
          at(
            DateTime(2028, 2, 10),
            principal: '417084.97',
            kind: LoanPaymentKind.extra,
          ),
        ),
        isNull,
      );
    });

    test('a monthly payment cannot pass principal plus unpaid interest', () {
      final DateTime on = DateTime(2027, 3, 15);
      expect(
        check(ravi, const [], at(on, principal: '10000', interest: '401')),
        'This is more than is owed',
      );
      expect(
        check(ravi, const [], at(on, principal: '10000', interest: '400')),
        isNull,
      );
    });

    test('an EMI closing payment may carry a 5,000 interest charge', () {
      expect(
        check(
          l,
          twelve,
          at(
            DateTime(2028, 2, 10),
            principal: '417084.97',
            interest: '5000',
            kind: LoanPaymentKind.extra,
          ),
        ),
        isNull,
      );
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
