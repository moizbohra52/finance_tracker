import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/split_calculator.dart';
import 'package:rational/rational.dart';

/// One repayment of a loan split into principal and interest.
class LoanPart {
  const LoanPart({
    required this.amount,
    required this.principal,
    required this.interest,
  });

  final Decimal amount;
  final Decimal principal;
  final Decimal interest;
}

/// One row of the schedule of remaining EMIs.
class LoanInstalment {
  const LoanInstalment({
    required this.number,
    required this.dueDate,
    required this.amount,
    required this.principal,
    required this.interest,
    required this.balanceAfter,
  });

  final int number;
  final DateTime dueDate;
  final Decimal amount;
  final Decimal principal;
  final Decimal interest;
  final Decimal balanceAfter;
}

/// Where a loan stands: what is owed, what has been paid and what is next.
/// [nextDueDate] is null for a closed loan; [instalmentsLeft] is null unless
/// the loan is an EMI loan.
class LoanStatus {
  const LoanStatus({
    required this.outstanding,
    required this.principalRepaid,
    required this.interestPaid,
    this.nextDueDate,
    this.nextAmount,
    this.instalmentsLeft,
  });

  final Decimal outstanding;
  final Decimal principalRepaid;
  final Decimal interestPaid;
  final DateTime? nextDueDate;
  final Decimal? nextAmount;
  final int? instalmentsLeft;
}

/// Money rules for loans and EMIs (docs/superpowers/specs/
/// 2026-11-11-loans-emi-design.md). Amounts are `Decimal`, rounded to paisa.
abstract final class LoanCalculator {
  static final Decimal _one = Decimal.one;
  static final Decimal _twelveHundred = Decimal.fromInt(1200);
  static final Decimal _maxAnnualRate = Decimal.fromInt(60);
  static final Decimal _tenThousand = Decimal.fromInt(10000);

  /// [date] moved by [months] months; the day is kept but clamped to the
  /// length of the target month (31 Jan -> 28/29 Feb). Date only.
  static DateTime addMonths(DateTime date, int months) {
    final DateTime first = DateTime(date.year, date.month + months);
    final int lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, math.min(date.day, lastDay));
  }

  /// One month of interest on [outstanding] at [annualRate] percent a year.
  static Decimal monthlyInterest(Decimal outstanding, Decimal annualRate) =>
      _money(outstanding * annualRate / _twelveHundred);

  /// The fixed monthly instalment: `P·r·(1+r)^n / ((1+r)^n − 1)` with
  /// `r = annualRate / 1200`, or `P / n` when the rate is 0.
  static Decimal emi({
    required Decimal principal,
    required Decimal annualRate,
    required int months,
  }) {
    if (annualRate == Decimal.zero) {
      return _money(principal / Decimal.fromInt(months));
    }
    final Decimal r = _exact(annualRate / _twelveHundred);
    Decimal growth = _one;
    for (int i = 0; i < months; i++) {
      growth = (growth * (_one + r)).round(scale: 30);
    }
    return _money(principal * r * growth / (growth - _one));
  }

  /// The principal still owed: the loan's principal less the principal parts
  /// of its live payments (scheduled and extra alike).
  static Decimal outstanding(Loan loan, Iterable<LoanPayment> payments) {
    return payments
        .where((LoanPayment p) => p.isLive)
        .fold(
          loan.principal,
          (Decimal owed, LoanPayment p) => owed - p.principalPart,
        );
  }

  /// How many EMIs are still to pay; 0 for a loan that is not an EMI loan or
  /// owes nothing. Without a live extra payment it is the tenure less the
  /// live scheduled payments (at least 1), so a loan ends on its tenure even
  /// though the EMI is rounded to paisa. After a prepayment the EMI stays and
  /// the months shrink: `ceil(ln(E / (E − O·r)) / ln(1 + r))`.
  static int instalmentsLeft(Loan loan, List<LoanPayment> payments) {
    final Decimal owed = outstanding(loan, payments);
    if (loan.method != LoanMethod.emi || owed <= Decimal.zero) return 0;
    final Iterable<LoanPayment> live = payments.where(
      (LoanPayment p) => p.isLive,
    );
    final int paid = live
        .where((LoanPayment p) => p.kind == LoanPaymentKind.scheduled)
        .length;
    final int byTenure = math.max(1, loan.tenureMonths! - paid);
    if (!live.any((LoanPayment p) => p.kind == LoanPaymentKind.extra)) {
      return byTenure;
    }
    if (loan.annualRate == Decimal.zero) {
      return math.max(1, (owed / _emiOf(loan)).ceil().toInt());
    }
    // Doubles only count months here; no amount is ever a double.
    final double e = _emiOf(loan).toDouble();
    final double o = owed.toDouble();
    final double r = loan.annualRate.toDouble() / 1200;
    final double interestShare = e - o * r;
    // An EMI that does not even cover the interest never pays the loan off.
    if (interestShare <= 0) return byTenure;
    final double months = math.log(e / interestShare) / math.log(1 + r);
    return math.max(1, (months - 1e-9).ceil());
  }

  /// The due date of instalment [number] (1-based).
  static DateTime dueDate(Loan loan, int number) =>
      addMonths(loan.firstDueDate!, number - 1);

  /// The remaining EMIs, computed from the outstanding and never stored. They
  /// are numbered after the live scheduled payments; each one's interest is
  /// on the balance and its principal is the rest of the EMI. The last one
  /// (or one that would overshoot the balance) takes exactly the balance.
  /// Empty for a closed loan, a monthly-interest loan or one that owes
  /// nothing.
  static List<LoanInstalment> schedule(Loan loan, List<LoanPayment> payments) {
    final int left = loan.isClosed ? 0 : instalmentsLeft(loan, payments);
    if (left == 0) return const <LoanInstalment>[];
    final Decimal emiAmount = _emiOf(loan);
    final int paid = payments
        .where(
          (LoanPayment p) => p.isLive && p.kind == LoanPaymentKind.scheduled,
        )
        .length;
    Decimal balance = outstanding(loan, payments);
    final List<LoanInstalment> rows = <LoanInstalment>[];
    for (int i = 0; i < left && balance > Decimal.zero; i++) {
      final Decimal interest = monthlyInterest(balance, loan.annualRate);
      Decimal principal = emiAmount - interest;
      if (i == left - 1 || principal >= balance) principal = balance;
      balance -= principal;
      rows.add(
        LoanInstalment(
          number: paid + i + 1,
          dueDate: dueDate(loan, paid + i + 1),
          amount: principal + interest,
          principal: principal,
          interest: interest,
          balanceAfter: balance,
        ),
      );
    }
    return rows;
  }

  /// Interest of a `monthly_interest` loan up to [asOf], in whole months: month
  /// k is complete once its anniversary (the start date plus k months) has
  /// come, and costs one month of interest on the principal owed at its start.
  /// 0 for an EMI loan.
  static Decimal accruedInterest(
    Loan loan,
    List<LoanPayment> payments,
    DateTime asOf,
  ) {
    if (loan.method != LoanMethod.monthlyInterest) return Decimal.zero;
    final DateTime today = _dateOnly(asOf);
    final List<LoanPayment> live = payments
        .where((LoanPayment p) => p.isLive)
        .toList();
    Decimal total = Decimal.zero;
    for (int k = 1; !addMonths(loan.startDate, k).isAfter(today); k++) {
      final DateTime monthStart = addMonths(loan.startDate, k - 1);
      final Decimal owed = live
          .where((LoanPayment p) => !_dateOnly(p.paidAt).isAfter(monthStart))
          .fold(
            loan.principal,
            (Decimal o, LoanPayment p) => o - p.principalPart,
          );
      total += monthlyInterest(owed, loan.annualRate);
    }
    return total;
  }

  /// Interest accrued up to [asOf] less the interest parts paid by then; never
  /// below 0.
  static Decimal unpaidInterest(
    Loan loan,
    List<LoanPayment> payments,
    DateTime asOf,
  ) {
    final DateTime today = _dateOnly(asOf);
    final Decimal unpaid = payments
        .where(
          (LoanPayment p) => p.isLive && !_dateOnly(p.paidAt).isAfter(today),
        )
        .fold(
          accruedInterest(loan, payments, asOf),
          (Decimal u, LoanPayment p) => u - p.interestPart,
        );
    return unpaid < Decimal.zero ? Decimal.zero : unpaid;
  }

  /// The next date a payment is due; null for a closed loan. An EMI loan's is
  /// that of the next scheduled instalment. A monthly-interest loan's is the
  /// first anniversary of the start date after the latest live payment (or
  /// after the start), so an unpaid month stays overdue.
  static DateTime? nextDueDate(Loan loan, List<LoanPayment> payments) {
    if (loan.isClosed) return null;
    final Iterable<LoanPayment> live = payments.where(
      (LoanPayment p) => p.isLive,
    );
    if (loan.method == LoanMethod.emi) {
      return dueDate(
        loan,
        live
                .where((LoanPayment p) => p.kind == LoanPaymentKind.scheduled)
                .length +
            1,
      );
    }
    final DateTime? last = _latestPaymentDay(live);
    int k = 1;
    while (last != null && !addMonths(loan.startDate, k).isAfter(last)) {
      k++;
    }
    return addMonths(loan.startDate, k);
  }

  /// The day (date only) a payment made at [now] is dated: today, but never
  /// before the loan starts or its latest live payment, which
  /// [validatePayment] refuses.
  static DateTime paymentDay(
    Loan loan,
    List<LoanPayment> payments,
    DateTime now,
  ) {
    DateTime day = _dateOnly(now);
    final DateTime start = _dateOnly(loan.startDate);
    if (start.isAfter(day)) day = start;
    final DateTime? last = _latestPaymentDay(
      payments.where((LoanPayment p) => p.isLive),
    );
    return last != null && last.isAfter(day) ? last : day;
  }

  /// Proposes how a payment of [amount] splits (or, with no [amount], what the
  /// form should fill in). [earlier] holds the loan's other payments, not the
  /// one being edited. Interest comes first; with [closing] the amount clears
  /// the loan (outstanding, plus unpaid interest for a monthly-interest loan).
  static LoanPart suggest(
    Loan loan,
    List<LoanPayment> earlier, {
    required LoanPaymentKind kind,
    required DateTime paidAt,
    Decimal? amount,
    bool closing = false,
  }) {
    final Decimal owed = outstanding(loan, earlier);
    if (loan.method == LoanMethod.monthlyInterest) {
      final Decimal unpaid = unpaidInterest(loan, earlier, paidAt);
      return _interestFirst(closing ? owed + unpaid : amount ?? unpaid, unpaid);
    }
    if (kind == LoanPaymentKind.extra) {
      final Decimal principal = closing ? owed : amount ?? Decimal.zero;
      return LoanPart(
        amount: principal,
        principal: principal,
        interest: Decimal.zero,
      );
    }
    if (amount != null) {
      return _interestFirst(amount, monthlyInterest(owed, loan.annualRate));
    }
    final List<LoanInstalment> rows = schedule(loan, earlier);
    if (rows.isEmpty) {
      return LoanPart(
        amount: Decimal.zero,
        principal: Decimal.zero,
        interest: Decimal.zero,
      );
    }
    return LoanPart(
      amount: rows.first.amount,
      principal: rows.first.principal,
      interest: rows.first.interest,
    );
  }

  /// Owed, paid so far and what comes next, from the live payments.
  static LoanStatus status(Loan loan, List<LoanPayment> payments) {
    final Iterable<LoanPayment> live = payments.where(
      (LoanPayment p) => p.isLive,
    );
    final DateTime? due = nextDueDate(loan, payments);
    final bool isEmi = loan.method == LoanMethod.emi;
    Decimal? nextAmount;
    if (isEmi) {
      final List<LoanInstalment> rows = schedule(loan, payments);
      if (rows.isNotEmpty) nextAmount = rows.first.amount;
    } else if (due != null) {
      final Decimal unpaid = unpaidInterest(loan, payments, due);
      // A reminder amount of 0 is refused by the server: no amount instead.
      if (unpaid > Decimal.zero) nextAmount = unpaid;
    }
    return LoanStatus(
      outstanding: outstanding(loan, payments),
      principalRepaid: live.fold(
        Decimal.zero,
        (Decimal a, LoanPayment p) => a + p.principalPart,
      ),
      interestPaid: live.fold(
        Decimal.zero,
        (Decimal a, LoanPayment p) => a + p.interestPart,
      ),
      nextDueDate: due,
      nextAmount: nextAmount,
      instalmentsLeft: isEmi ? instalmentsLeft(loan, payments) : null,
    );
  }

  /// The first thing wrong with [loan], as an English message key, or null.
  /// Also refuses what the maths cannot take: no EMI, a tenure outside 1..480.
  static String? validateLoan(Loan loan) {
    final bool isEmi = loan.method == LoanMethod.emi;
    final Decimal? emiAmount = loan.emiAmount;
    if (loan.name.trim().isEmpty) return 'Give the loan a name';
    if (loan.name.trim().length > 80) return 'Keep the name to 80 characters';
    if (loan.accountId.isEmpty) return 'Choose an account';
    if (loan.principal <= Decimal.zero) return 'Amount must be more than zero';
    if (SplitCalculator.hasSubPaise(loan.principal) ||
        (emiAmount != null && SplitCalculator.hasSubPaise(emiAmount))) {
      return 'Amounts can have at most 2 decimals';
    }
    if (loan.annualRate < Decimal.zero || loan.annualRate > _maxAnnualRate) {
      return isEmi
          ? 'Interest rate must be between 0% and 60% a year'
          : 'Interest rate must be between 0% and 5% a month';
    }
    if (!(loan.annualRate * _tenThousand).isInteger) {
      return 'Interest rate can have at most 4 decimals';
    }
    if (!isEmi) return null;
    final int? months = loan.tenureMonths;
    if (months == null || months < 1 || months > 480) {
      return 'Tenure must be 1 to 480 months';
    }
    if (emiAmount == null || emiAmount <= Decimal.zero) return 'Enter the EMI';
    if (loan.annualRate > Decimal.zero &&
        emiAmount <= monthlyInterest(loan.principal, loan.annualRate)) {
      return "The EMI does not cover the first month's interest";
    }
    final DateTime? first = loan.firstDueDate;
    if (first == null) return 'Choose the first EMI date';
    if (_dateOnly(first).isBefore(_dateOnly(loan.startDate))) {
      return 'The first EMI cannot be before the loan starts';
    }
    return null;
  }

  /// The first thing wrong with [payment] on [loan], as an English message
  /// key, or null. [earlier] holds the loan's other payments (deleted ones are
  /// ignored). The interest part of an EMI or closing payment is not capped.
  static String? validatePayment(
    Loan loan,
    List<LoanPayment> earlier,
    LoanPayment payment,
  ) {
    if (payment.amount <= Decimal.zero) return 'Amount must be more than zero';
    if (<Decimal>[
      payment.amount,
      payment.principalPart,
      payment.interestPart,
    ].any(SplitCalculator.hasSubPaise)) {
      return 'Amounts can have at most 2 decimals';
    }
    if (payment.principalPart < Decimal.zero ||
        payment.interestPart < Decimal.zero ||
        payment.principalPart + payment.interestPart != payment.amount) {
      return 'Principal and interest must add up to the amount';
    }
    final DateTime day = _dateOnly(payment.paidAt);
    final DateTime? last = _latestPaymentDay(
      earlier.where((LoanPayment p) => p.isLive),
    );
    if (day.isBefore(_dateOnly(loan.startDate)) ||
        (last != null && day.isBefore(last))) {
      return 'A payment cannot be dated before the previous one or the loan '
          'start';
    }
    final Decimal owed = outstanding(loan, earlier);
    if (owed <= Decimal.zero) return 'This loan is already repaid';
    if (payment.principalPart > owed) {
      return 'This is more than the principal still owed';
    }
    if (loan.method == LoanMethod.monthlyInterest &&
        payment.amount > owed + unpaidInterest(loan, earlier, payment.paidAt)) {
      return 'This is more than is owed';
    }
    return null;
  }

  /// [amount] with interest taken first, up to [interestDue]; the rest is
  /// principal.
  static LoanPart _interestFirst(Decimal amount, Decimal interestDue) {
    final Decimal interest = amount < interestDue ? amount : interestDue;
    return LoanPart(
      amount: amount,
      principal: amount - interest,
      interest: interest,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? _latestPaymentDay(Iterable<LoanPayment> payments) {
    DateTime? latest;
    for (final LoanPayment p in payments) {
      final DateTime day = _dateOnly(p.paidAt);
      if (latest == null || day.isAfter(latest)) latest = day;
    }
    return latest;
  }

  static Decimal _emiOf(Loan loan) =>
      loan.emiAmount ??
      emi(
        principal: loan.principal,
        annualRate: loan.annualRate,
        months: loan.tenureMonths!,
      );

  static Decimal _exact(Rational value) =>
      value.toDecimal(scaleOnInfinitePrecision: 30);

  static Decimal _money(Rational value) => _exact(value).round(scale: 2);
}
