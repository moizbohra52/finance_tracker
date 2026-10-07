import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/features/accounts/views/account_detail_view.dart';
import 'package:finance_tracker/features/accounts/views/account_form_view.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AccountListView extends GetView<AccountController> {
  const AccountListView({super.key});

  static final NumberFormat _currencyFmt = NumberFormat.currency(
    locale: AppConstants.defaultLocale,
    name: AppConstants.defaultCurrencyCode,
    decimalDigits: AppConstants.currencyDecimalDigits,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Accounts'),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const LoadingState(message: 'Loading accounts');
        }
        if (controller.error.value.isNotEmpty) {
          return ErrorState(
            message: controller.error.value,
            onRetry: controller.loadAccounts,
          );
        }
        if (controller.accounts.isEmpty) {
          return EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No accounts yet',
            message: 'Add your first account to start tracking your finances.',
            actionLabel: 'Add Account',
            onAction: _showAddAccountForm,
          );
        }
        return ListView.separated(
          itemCount: controller.accounts.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final Account account = controller.accounts[index];
            return FutureBuilder<Decimal>(
              future: controller.getAccountBalance(account),
              builder: (context, snapshot) {
                final String balanceText = snapshot.hasData
                    ? _currencyFmt.format(snapshot.data!)
                    : '—';
                final Color balanceColor = (snapshot.hasData &&
                        snapshot.data! < Decimal.zero)
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).textTheme.bodyLarge!.color!;
                return AppCard(
                  child: ListTile(
                    leading: Icon(_getIconForAccountType(account.type)),
                    title: Text(account.name),
                    subtitle: Text(
                      account.type.name.toUpperCase(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          balanceText,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: balanceColor),
                        ),
                        if (!account.isActive)
                          Text(
                            'Archived',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                    onTap: () => Get.to<dynamic>(
                      () => AccountDetailView(account: account),
                    ),
                  ),
                );
              },
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddAccountForm,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddAccountForm() {
    Get.to(() => const AccountFormView())?.then((_) => controller.loadAccounts());
  }

  IconData _getIconForAccountType(AccountType type) {
    switch (type) {
      case AccountType.cash:
        return Icons.money;
      case AccountType.bank:
        return Icons.account_balance;
      case AccountType.upi:
        return Icons.account_balance_wallet;
      case AccountType.card:
        return Icons.credit_card;
      case AccountType.other:
        return Icons.account_box;
    }
  }
}
