import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:flutter/material.dart';

/// Contact name with what they owe the user or what the user owes them.
class ContactBalanceTile extends StatelessWidget {
  const ContactBalanceTile({super.key, required this.row, this.onTap});

  final ContactBalance row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String name = row.contact.name;

    final (String label, Color? color) = row.isReceivable
        ? ('You will get', money.receivable)
        : row.isPayable
        ? ('You will give', money.payable)
        : ('Settled', null);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: (row.contact.mobile ?? '').isEmpty
          ? null
          : Text(row.contact.mobile!, style: text.bodySmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (color != null)
            Text(
              AppFormatters.money(row.balance.abs()),
              style: text.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          Text(label, style: text.labelSmall),
        ],
      ),
    );
  }
}
