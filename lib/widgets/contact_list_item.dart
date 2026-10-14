import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:flutter/material.dart';

/// Contact name with what they owe the user or what the user owes them.
class ContactBalanceTile extends StatelessWidget {
  const ContactBalanceTile({
    super.key,
    required this.row,
    this.onTap,
    this.padding = AppListTile.defaultPadding,
  });

  final ContactBalance row;
  final VoidCallback? onTap;

  /// [AppListTile.flatPadding] when the row sits directly on the page.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    final (String label, Color? color) = row.isReceivable
        ? ('You will get', money.receivable)
        : row.isPayable
        ? ('You will give', money.payable)
        : ('Settled', null);

    return AppListTile(
      onTap: onTap,
      padding: padding,
      leading: IconBadge.initial(row.contact.name),
      title: row.contact.name,
      subtitle: row.contact.mobile,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (color != null)
            Text(
              AppFormatters.money(row.balance.abs()),
              style: text.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
