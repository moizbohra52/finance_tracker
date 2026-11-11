import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/report_calculator.dart';
import 'package:finance_tracker/domain/services/report_period.dart';

/// The category whose spending rose most against the same days of last month.
class CategoryIncrease {
  const CategoryIncrease({required this.categoryId, required this.amount});

  /// Null for spending without a category.
  final String? categoryId;

  /// How much more was spent, always above zero.
  final Decimal amount;
}

/// The home screen's insights: net worth, and this month's spending so far
/// against the same days of last month.
class MonthInsights {
  const MonthInsights({
    required this.netWorth,
    required this.spentSoFar,
    required this.spentLastMonthSoFar,
    this.topIncrease,
  });

  static final MonthInsights zero = MonthInsights(
    netWorth: Decimal.zero,
    spentSoFar: Decimal.zero,
    spentLastMonthSoFar: Decimal.zero,
  );

  /// Active accounts' balance plus what others owe the user, less what the
  /// user owes them (khata).
  final Decimal netWorth;
  final Decimal spentSoFar;
  final Decimal spentLastMonthSoFar;
  final CategoryIncrease? topIncrease;

  /// The change against the same days of last month, in whole percent
  /// (negative when less was spent). Null when last month had no spending by
  /// then, since a change from nothing has no percent.
  int? get changePercent {
    if (spentLastMonthSoFar == Decimal.zero) return null;
    return ((spentSoFar - spentLastMonthSoFar) *
            Decimal.fromInt(100) /
            spentLastMonthSoFar)
        .toDouble()
        .round();
  }
}

/// Insights for the home screen (docs/05_FINANCIAL_LOGIC.md). Spending is
/// expense only, as in [FinanceSummaryCalculator.period]: transfers,
/// adjustments and deleted rows do not count.
abstract final class InsightsCalculator {
  /// This month from its first day to the end of today, and last month from
  /// its first day to the end of the same day of the month, or to its end
  /// when it is shorter. Ends are exclusive.
  static ({
    DateTime currentStart,
    DateTime currentEnd,
    DateTime previousStart,
    DateTime previousEnd,
  })
  windows(DateTime now) {
    final DateTime previousStart = DateTime(now.year, now.month - 1);
    final int previousDays = DateTime(now.year, now.month, 0).day;
    return (
      currentStart: DateTime(now.year, now.month),
      currentEnd: DateTime(now.year, now.month, now.day + 1),
      previousStart: previousStart,
      previousEnd: DateTime(
        previousStart.year,
        previousStart.month,
        math.min(now.day, previousDays) + 1,
      ),
    );
  }

  static MonthInsights month({
    required List<Transaction> transactions,
    required Decimal accountsBalance,
    required KhataSummary khata,
    required DateTime now,
  }) {
    final ({
      DateTime currentStart,
      DateTime currentEnd,
      DateTime previousStart,
      DateTime previousEnd,
    })
    w = windows(now);
    final ReportPeriod current = ReportPeriod(
      preset: DatePreset.custom,
      start: w.currentStart,
      end: w.currentEnd,
    );
    final ReportPeriod previous = ReportPeriod(
      preset: DatePreset.custom,
      start: w.previousStart,
      end: w.previousEnd,
    );
    return MonthInsights(
      netWorth: accountsBalance + khata.receivable - khata.payable,
      spentSoFar: FinanceSummaryCalculator.period(
        transactions,
        current.start,
        current.end,
      ).expense,
      spentLastMonthSoFar: FinanceSummaryCalculator.period(
        transactions,
        previous.start,
        previous.end,
      ).expense,
      topIncrease: _topIncrease(transactions, current, previous),
    );
  }

  static CategoryIncrease? _topIncrease(
    List<Transaction> transactions,
    ReportPeriod current,
    ReportPeriod previous,
  ) {
    final Map<String?, Decimal> before = <String?, Decimal>{
      for (final CategoryTotal c in ReportCalculator.categoryTotals(
        transactions,
        previous,
        TransactionType.expense,
      ))
        c.categoryId: c.amount,
    };
    CategoryIncrease? top;
    // Largest current spending first, so a tie goes to the bigger category.
    for (final CategoryTotal c in ReportCalculator.categoryTotals(
      transactions,
      current,
      TransactionType.expense,
    )) {
      final Decimal rise = c.amount - (before[c.categoryId] ?? Decimal.zero);
      if (rise > Decimal.zero && (top == null || rise > top.amount)) {
        top = CategoryIncrease(categoryId: c.categoryId, amount: rise);
      }
    }
    return top;
  }
}
