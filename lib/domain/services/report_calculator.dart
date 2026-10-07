import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/report_period.dart';

/// One category's share of the period's income or expense.
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.amount,
    required this.share,
  });

  /// Null groups transactions that have no category.
  final String? categoryId;
  final Decimal amount;

  /// 0..1 of the period total for the same type.
  final double share;
}

class AccountTotal {
  const AccountTotal({
    required this.accountId,
    required this.income,
    required this.expense,
  });

  final String accountId;
  final Decimal income;
  final Decimal expense;
  Decimal get net => income - expense;
}

/// Income and expense inside one chart bucket (hour, day or month).
class TrendPoint {
  const TrendPoint({
    required this.start,
    required this.income,
    required this.expense,
  });

  final DateTime start;
  final Decimal income;
  final Decimal expense;
}

enum TrendBucket { hour, day, month }

/// Report and analytics maths. Only `income` and `expense` rows count as
/// income and expense: transfers, adjustments and khata settlements move
/// money between places and must not be double-counted
/// (docs/05_FINANCIAL_LOGIC.md).
abstract final class ReportCalculator {
  static List<Transaction> _inPeriod(
    List<Transaction> transactions,
    ReportPeriod period,
  ) => transactions
      .where(
        (Transaction t) =>
            t.deletedAt == null && period.contains(t.transactionDate),
      )
      .toList();

  static PeriodSummary summary(
    List<Transaction> transactions,
    ReportPeriod period,
  ) => FinanceSummaryCalculator.period(transactions, period.start, period.end);

  /// Totals per category for [type] (income or expense), largest first.
  static List<CategoryTotal> categoryTotals(
    List<Transaction> transactions,
    ReportPeriod period,
    TransactionType type,
  ) {
    final Map<String?, Decimal> totals = <String?, Decimal>{};
    Decimal grand = Decimal.zero;
    for (final Transaction t in _inPeriod(transactions, period)) {
      if (t.type != type) continue;
      totals[t.categoryId] = (totals[t.categoryId] ?? Decimal.zero) + t.amount;
      grand += t.amount;
    }
    final List<CategoryTotal> rows = <CategoryTotal>[
      for (final MapEntry<String?, Decimal> e in totals.entries)
        CategoryTotal(
          categoryId: e.key,
          amount: e.value,
          share: grand == Decimal.zero
              ? 0
              : (e.value / grand)
                    .toDecimal(scaleOnInfinitePrecision: 6)
                    .toDouble(),
        ),
    ]..sort((CategoryTotal a, CategoryTotal b) => b.amount.compareTo(a.amount));
    return rows;
  }

  /// Income and expense per account, largest movement first.
  static List<AccountTotal> accountTotals(
    List<Transaction> transactions,
    ReportPeriod period,
  ) {
    final Map<String, Decimal> income = <String, Decimal>{};
    final Map<String, Decimal> expense = <String, Decimal>{};
    for (final Transaction t in _inPeriod(transactions, period)) {
      if (t.type == TransactionType.income) {
        income[t.accountId] = (income[t.accountId] ?? Decimal.zero) + t.amount;
      } else if (t.type == TransactionType.expense) {
        expense[t.accountId] =
            (expense[t.accountId] ?? Decimal.zero) + t.amount;
      }
    }
    final Set<String> ids = <String>{...income.keys, ...expense.keys};
    return <AccountTotal>[
      for (final String id in ids)
        AccountTotal(
          accountId: id,
          income: income[id] ?? Decimal.zero,
          expense: expense[id] ?? Decimal.zero,
        ),
    ]..sort(
      (AccountTotal a, AccountTotal b) =>
          (b.income + b.expense).compareTo(a.income + a.expense),
    );
  }

  static TrendBucket bucketFor(ReportPeriod period) {
    if (period.days <= 1) return TrendBucket.hour;
    return period.days <= 62 ? TrendBucket.day : TrendBucket.month;
  }

  /// One point per bucket across the whole period (empty buckets are zero),
  /// so a chart's x-axis is continuous.
  static List<TrendPoint> trend(
    List<Transaction> transactions,
    ReportPeriod period,
  ) {
    final TrendBucket bucket = bucketFor(period);
    final List<DateTime> starts = <DateTime>[];
    DateTime cursor = period.start;
    while (cursor.isBefore(period.end)) {
      starts.add(cursor);
      cursor = switch (bucket) {
        TrendBucket.hour => DateTime(
          cursor.year,
          cursor.month,
          cursor.day,
          cursor.hour + 1,
        ),
        TrendBucket.day => DateTime(cursor.year, cursor.month, cursor.day + 1),
        TrendBucket.month => DateTime(cursor.year, cursor.month + 1),
      };
    }
    DateTime keyOf(DateTime d) => switch (bucket) {
      TrendBucket.hour => DateTime(d.year, d.month, d.day, d.hour),
      TrendBucket.day => DateTime(d.year, d.month, d.day),
      TrendBucket.month => DateTime(d.year, d.month),
    };
    final Map<DateTime, Decimal> income = <DateTime, Decimal>{};
    final Map<DateTime, Decimal> expense = <DateTime, Decimal>{};
    for (final Transaction t in _inPeriod(transactions, period)) {
      final DateTime key = keyOf(t.transactionDate);
      if (t.type == TransactionType.income) {
        income[key] = (income[key] ?? Decimal.zero) + t.amount;
      } else if (t.type == TransactionType.expense) {
        expense[key] = (expense[key] ?? Decimal.zero) + t.amount;
      }
    }
    return <TrendPoint>[
      for (final DateTime s in starts)
        TrendPoint(
          start: s,
          income: income[s] ?? Decimal.zero,
          expense: expense[s] ?? Decimal.zero,
        ),
    ];
  }

  /// The last [months] calendar months ending with the month of [now],
  /// oldest first.
  static List<TrendPoint> monthlyComparison(
    List<Transaction> transactions,
    DateTime now, {
    int months = 6,
  }) {
    final ReportPeriod window = ReportPeriod(
      preset: DatePreset.custom,
      start: DateTime(now.year, now.month - (months - 1)),
      end: DateTime(now.year, now.month + 1),
    );
    return trend(transactions, window);
  }
}
