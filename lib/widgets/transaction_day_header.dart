import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter/material.dart';

/// A row of a day-grouped transaction list: a day header or a transaction.
sealed class TransactionListRow {}

class TransactionDayRow extends TransactionListRow {
  TransactionDayRow(this.label, this.count);
  final String label;
  final int count;
}

class TransactionItemRow extends TransactionListRow {
  TransactionItemRow(this.transaction);
  final Transaction transaction;
}

/// [items] in their order, with a header before each day's transactions.
/// A row shows only its time, so the header is where its date is read.
List<TransactionListRow> groupTransactionsByDay(Iterable<Transaction> items) {
  final Map<String, List<Transaction>> grouped = <String, List<Transaction>>{};
  for (final Transaction t in items) {
    final String label = AppFormatters.dayLabel(t.transactionDate);
    grouped.putIfAbsent(label, () => <Transaction>[]).add(t);
  }
  return <TransactionListRow>[
    for (final MapEntry<String, List<Transaction>> day in grouped.entries) ...[
      TransactionDayRow(day.key, day.value.length),
      for (final Transaction t in day.value) TransactionItemRow(t),
    ],
  ];
}

/// The day ("Today", "8 Oct 2026") above its transactions, with how many
/// of them are loaded.
class TransactionDayHeader extends StatelessWidget {
  const TransactionDayHeader({
    super.key,
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.xs,
        left: 2,
        right: 2,
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.onSurfaceVariant,
                    letterSpacing: 0.5,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: colors.outlineVariant.withValues(alpha: 0.4),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}
