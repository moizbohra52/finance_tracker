import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/report_period.dart';
import 'package:uuid/uuid.dart';

enum BudgetState { upcoming, active, ended }

/// Highest alert threshold the spending has reached.
enum BudgetLevel { ok, warning75, warning90, exceeded }

class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.period,
    required this.state,
    required this.spent,
    required this.remaining,
    required this.percent,
    required this.crossed,
  });

  final Budget budget;
  final ReportPeriod period;
  final BudgetState state;
  final Decimal spent;

  /// `amount - spent`; negative once the budget is exceeded.
  final Decimal remaining;

  /// `spent / amount * 100`, uncapped. Display only; thresholds use exact
  /// decimal comparison.
  final double percent;

  /// Thresholds (75, 90, 100) the spending has reached, ascending.
  final List<int> crossed;

  BudgetLevel get level => crossed.contains(100)
      ? BudgetLevel.exceeded
      : crossed.contains(90)
      ? BudgetLevel.warning90
      : crossed.contains(75)
      ? BudgetLevel.warning75
      : BudgetLevel.ok;
}

/// One threshold event for one budget in one period. [id] is derived from
/// those three values, so raising the same event twice (this device, another
/// device, a retry) writes the same row.
class BudgetAlert {
  BudgetAlert({
    required this.budgetId,
    required this.periodStart,
    required this.threshold,
  }) : id = const Uuid().v5(
         Namespace.url.value,
         'budget-alert:$budgetId:'
         '${periodStart.year}-${periodStart.month}-${periodStart.day}:'
         '$threshold',
       );

  final String budgetId;
  final DateTime periodStart;
  final int threshold;
  final String id;
}

/// Budget maths (docs/05_FINANCIAL_LOGIC.md): spent counts expense
/// transactions for the budget's category (or all categories) in its period.
abstract final class BudgetCalculator {
  static const List<int> thresholds = <int>[75, 90, 100];

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The period a budget measures "now", and where it stands.
  ///
  /// A monthly budget measures the calendar month containing [now] (or its
  /// first month while upcoming). A custom budget measures its own range.
  static (ReportPeriod, BudgetState) periodFor(Budget budget, DateTime now) {
    final DateTime start = _day(budget.startDate);
    if (budget.periodType == BudgetPeriodType.monthly) {
      final DateTime firstMonth = DateTime(start.year, start.month);
      if (now.isBefore(firstMonth)) {
        return (
          ReportPeriod(
            preset: DatePreset.custom,
            start: firstMonth,
            end: DateTime(firstMonth.year, firstMonth.month + 1),
          ),
          BudgetState.upcoming,
        );
      }
      return (
        ReportPeriod.resolve(DatePreset.thisMonth, now),
        BudgetState.active,
      );
    }
    final DateTime last = _day(budget.endDate ?? budget.startDate);
    final ReportPeriod period = ReportPeriod(
      preset: DatePreset.custom,
      start: start,
      end: DateTime(last.year, last.month, last.day + 1),
    );
    final BudgetState state = now.isBefore(period.start)
        ? BudgetState.upcoming
        : (now.isBefore(period.end) ? BudgetState.active : BudgetState.ended);
    return (period, state);
  }

  static BudgetStatus status(
    Budget budget,
    List<Transaction> transactions,
    DateTime now,
  ) {
    final (ReportPeriod period, BudgetState state) = periodFor(budget, now);
    Decimal spent = Decimal.zero;
    for (final Transaction t in transactions) {
      if (t.deletedAt != null || t.type != TransactionType.expense) continue;
      if (!period.contains(t.transactionDate)) continue;
      if (budget.categoryId != null && t.categoryId != budget.categoryId) {
        continue;
      }
      spent += t.amount;
    }
    final Decimal hundred = Decimal.fromInt(100);
    return BudgetStatus(
      budget: budget,
      period: period,
      state: state,
      spent: spent,
      remaining: budget.amount - spent,
      percent: (spent * hundred / budget.amount)
          .toDecimal(scaleOnInfinitePrecision: 4)
          .toDouble(),
      crossed: <int>[
        for (final int t in thresholds)
          if (spent * hundred >= budget.amount * Decimal.fromInt(t)) t,
      ],
    );
  }

  /// Every budget's status for [now], active budgets first.
  static List<BudgetStatus> statuses(
    List<Budget> budgets,
    List<Transaction> transactions,
    DateTime now,
  ) {
    final List<BudgetStatus> all = <BudgetStatus>[
      for (final Budget b in budgets)
        if (b.deletedAt == null) status(b, transactions, now),
    ];
    int rank(BudgetState s) => switch (s) {
      BudgetState.active => 0,
      BudgetState.upcoming => 1,
      BudgetState.ended => 2,
    };
    all.sort((BudgetStatus a, BudgetStatus b) {
      final int byState = rank(a.state).compareTo(rank(b.state));
      return byState != 0 ? byState : b.percent.compareTo(a.percent);
    });
    return all;
  }

  /// Threshold events to raise for [status]: the crossed thresholds the user
  /// enabled, for budgets whose period has started.
  static List<BudgetAlert> alertsFor(BudgetStatus status) {
    if (status.state == BudgetState.upcoming) return const <BudgetAlert>[];
    return <BudgetAlert>[
      for (final int t in status.crossed)
        if (status.budget.alertEnabled(t))
          BudgetAlert(
            budgetId: status.budget.id,
            periodStart: status.period.start,
            threshold: t,
          ),
    ];
  }

  /// The span of dates that must be loaded to evaluate [budgets].
  static (DateTime, DateTime)? window(List<Budget> budgets, DateTime now) {
    DateTime? start;
    DateTime? end;
    for (final Budget b in budgets) {
      if (b.deletedAt != null) continue;
      final ReportPeriod p = periodFor(b, now).$1;
      if (start == null || p.start.isBefore(start)) start = p.start;
      if (end == null || p.end.isAfter(end)) end = p.end;
    }
    return start == null ? null : (start, end!);
  }
}
