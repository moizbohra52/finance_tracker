import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
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
    this.padding = AppListTile.defaultPadding,
  });

  final Transaction transaction;

  /// Category name, or a fallback chosen by the caller.
  final String title;

  /// Extra metadata such as the account name.
  final String subtitle;
  final String? iconKey;
  final VoidCallback? onTap;

  /// [AppListTile.flatPadding] when the row sits directly on the page.
  final EdgeInsetsGeometry padding;

  /// Row title for [t]: its category's name; for a transfer leg "To ..." or
  /// "From ..." naming the other account when [nearby] holds the other leg;
  /// otherwise its type ("Expense", "Transfer in").
  static String titleFor(
    Transaction t, {
    required String? categoryName,
    required Iterable<Transaction> nearby,
    required String Function(String accountId) accountName,
  }) {
    if (categoryName != null) return categoryName;
    if (TransferLegs.isLeg(t)) {
      for (final Transaction other in nearby) {
        if (other.transferId == t.transferId && other.id != t.id) {
          final String account = accountName(other.accountId);
          return t.type == TransactionType.transfer_out
              ? 'To $account'
              : 'From $account';
        }
      }
    }
    return t.type.label;
  }

  @override
  Widget build(BuildContext context) {
    final bool inflow = transaction.type.isInflow;
    // A transfer is neither income nor expense, so its badge is neutral.
    final bool income = inflow && !TransferLegs.isLeg(transaction);
    return AppListTile(
      onTap: onTap,
      padding: padding,
      leading: IconBadge(
        icon: CategoryIcons.of(iconKey, transaction.type),
        color: income ? FinanceColors.of(context).income : null,
      ),
      title: title,
      subtitle:
          '${AppFormatters.time(transaction.transactionDate)} · '
          '${transaction.type.label} · $subtitle',
      trailing: MoneyText(
        transaction.amount,
        flow: inflow ? MoneyFlow.inflow : MoneyFlow.outflow,
      ),
    );
  }
}
