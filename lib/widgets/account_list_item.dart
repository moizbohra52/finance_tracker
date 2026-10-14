import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:flutter/material.dart';

IconData accountTypeIcon(AccountType type) => switch (type) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.bank => Icons.account_balance_outlined,
  AccountType.upi => Icons.qr_code_2_rounded,
  AccountType.card => Icons.credit_card_outlined,
  AccountType.other => Icons.wallet_outlined,
};

String accountTypeLabel(AccountType type) => switch (type) {
  AccountType.cash => 'Cash',
  AccountType.bank => 'Bank',
  AccountType.upi => 'UPI',
  AccountType.card => 'Card',
  AccountType.other => 'Other',
};

/// One account row: type badge, name, detail and current balance.
class AccountTile extends StatelessWidget {
  const AccountTile({
    super.key,
    required this.account,
    required this.balance,
    this.subtitle,
    this.isHidden = false,
    this.onTap,
  });

  final Account account;
  final Decimal balance;

  /// Defaults to the account type.
  final String? subtitle;

  /// Masks the balance (the home screen's privacy toggle).
  final bool isHidden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      onTap: onTap,
      leading: IconBadge(icon: accountTypeIcon(account.type)),
      title: account.name,
      subtitle: subtitle ?? accountTypeLabel(account.type),
      trailing: isHidden
          ? Text(
              '••••',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            )
          : MoneyText(balance, flow: MoneyFlow.neutral),
    );
  }
}
