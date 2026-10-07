import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter/material.dart';

/// One transaction row: icon, title, time and type, and a signed amount.
class TransactionListItem extends StatelessWidget {
  const TransactionListItem({
    super.key,
    required this.transaction,
    required this.title,
    required this.subtitle,
    this.iconKey,
    this.onTap,
  });

  final Transaction transaction;

  /// Category name, or a fallback chosen by the caller.
  final String title;

  /// Extra metadata such as the account name.
  final String subtitle;
  final String? iconKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final FinanceColors money = FinanceColors.of(context);
    final bool inflow = transaction.type.isInflow;
    final Color badgeBg = inflow
        ? money.income.withValues(alpha: 0.12)
        : colors.primary.withValues(alpha: 0.1);
    final Color iconColor = inflow ? money.income : colors.primary;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        alignment: Alignment.center,
        child: Icon(
          CategoryIcons.of(iconKey, transaction.type),
          color: iconColor,
          size: 22,
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${AppFormatters.time(transaction.transactionDate)} · '
        '${transaction.type.label} · $subtitle',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      trailing: MoneyText(
        transaction.amount,
        flow: inflow ? MoneyFlow.inflow : MoneyFlow.outflow,
        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
