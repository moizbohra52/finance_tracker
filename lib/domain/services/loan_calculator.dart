import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
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

/// Money rules for loans and EMIs (docs/superpowers/specs/
/// 2026-11-11-loans-emi-design.md). Amounts are `Decimal`, rounded to paisa.
abstract final class LoanCalculator {
  static final Decimal _one = Decimal.one;
  static final Decimal _twelveHundred = Decimal.fromInt(1200);

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
