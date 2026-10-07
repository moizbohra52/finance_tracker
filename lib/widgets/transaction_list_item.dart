import 'package:finance_tracker/core/theme/app_tokens.dart';
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
    final bool inflow = transaction.type.isInflow;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: colors.secondaryContainer,
        foregroundColor: colors.onSecondaryContainer,
        child: Icon(CategoryIcons.of(iconKey, transaction.type)),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${AppFormatters.time(transaction.transactionDate)} · '
        '${transaction.type.label} · $subtitle',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall,
      ),
      trailing: MoneyText(
        transaction.amount,
        flow: inflow ? MoneyFlow.inflow : MoneyFlow.outflow,
      ),
    );
  }
}
