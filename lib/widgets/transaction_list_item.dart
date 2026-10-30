import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Modern transaction card tile: squircle category badge, title, account chip,
/// time, optional note preview, and prominent formatted amount with flow pill.
class TransactionListItem extends StatelessWidget {
  const TransactionListItem({
    super.key,
    required this.transaction,
    required this.title,
    required this.subtitle,
    this.iconKey,
    this.onTap,
    this.groupLabel,
    this.padding = AppListTile.defaultPadding,
  });

  final Transaction transaction;

  /// Category name, or a fallback chosen by the caller.
  final String title;

  /// Extra metadata such as the account name.
  final String subtitle;
  final String? iconKey;
  final VoidCallback? onTap;

  /// The split group behind a derived row, shown as a small chip; null for a
  /// plain row.
  final String? groupLabel;

  /// Unused for card layout, preserved for API backward-compatibility.
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
    if (t.type == TransactionType.opening_balance) {
      return (t.description != null && t.description!.trim().isNotEmpty)
          ? t.description!
          : 'Opening balance'.tr;
    }
    if (TransferLegs.isLeg(t)) {
      for (final Transaction other in nearby) {
        if (other.transferId == t.transferId && other.id != t.id) {
          final String account = accountName(other.accountId);
          return t.type == TransactionType.transfer_out
              ? 'To @account'.trParams(<String, String>{'account': account})
              : 'From @account'.trParams(<String, String>{'account': account});
        }
      }
    }
    if (t.description != null && t.description!.trim().isNotEmpty) {
      return t.description!;
    }
    if (t.type == TransactionType.expense || t.type == TransactionType.income) {
      if (t.note != null && t.note!.trim().isNotEmpty) {
        return t.note!.trim();
      }
      return 'Uncategorised'.tr;
    }
    return t.type.label;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final FinanceColors money = FinanceColors.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final bool isLeg = TransferLegs.isLeg(transaction);
    final bool isOpening = transaction.type == TransactionType.opening_balance;
    final bool inflow = transaction.type.isInflow;
    final bool isIncome = (inflow && !isLeg) || isOpening;
    final bool isExpense = !inflow && !isLeg && !isOpening;

    final Color badgeColor = isIncome
        ? money.income
        : isExpense
        ? money.expense
        : colors.primary;

    final Color amountColor = isIncome
        ? money.income
        : isExpense
        ? money.expense
        : (inflow ? money.income : colors.onSurface);

    final String sign = isIncome
        ? '+'
        : isExpense
        ? '−'
        : (inflow ? '+' : '−');

    final String badgeLabel = isLeg
        ? (inflow ? 'Transfer in'.tr : 'Transfer out'.tr)
        : transaction.type.label;

    final IconData flowIcon = isOpening
        ? Icons.account_balance_wallet_rounded
        : isIncome
        ? Icons.arrow_downward_rounded
        : isExpense
        ? Icons.arrow_upward_rounded
        : Icons.swap_horiz_rounded;

    final bool hasNote =
        transaction.note != null &&
        transaction.note!.trim().isNotEmpty &&
        transaction.note!.trim().toLowerCase() != title.trim().toLowerCase();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
            width: 1,
          ),
        ),
        elevation: isDark ? 0 : 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // Modern Squircle Icon Badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    CategoryIcons.of(iconKey, transaction.type),
                    color: badgeColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Transaction Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          // Account pill
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest
                                    .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurfaceVariant,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (groupLabel != null) ...<Widget>[
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer.withValues(
                                    alpha: 0.7,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.full,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.groups_outlined,
                                      size: 10,
                                      color: colors.onPrimaryContainer,
                                    ),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        groupLabel!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.labelSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: colors.onPrimaryContainer,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            AppFormatters.time(transaction.transactionDate),
                            style: text.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant.withValues(
                                alpha: 0.8,
                              ),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      if (hasNote) ...<Widget>[
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.notes_rounded,
                              size: 11,
                              color: colors.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                transaction.note!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Amount and Flow Pill
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '$sign${AppFormatters.money(transaction.amount)}',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: amountColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(flowIcon, size: 10, color: badgeColor),
                          const SizedBox(width: 2.5),
                          Text(
                            badgeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: badgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
