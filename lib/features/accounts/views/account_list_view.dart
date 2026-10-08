import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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

void openAddAccount() => Get.toNamed<void>(AppRoutes.accountForm);

class AccountListView extends GetView<AccountController> {
  const AccountListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Accounts'),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const AppContent(child: SkeletonList(count: 4));
          }
          final String? error = controller.error.value;
          if (error != null && controller.accounts.isEmpty) {
            return ErrorState(message: error, onRetry: controller.load);
          }
          if (controller.accounts.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts yet',
              message:
                  'Add your first account with its opening balance to start '
                  'tracking your money.',
              actionLabel: 'Add account',
              onAction: openAddAccount,
            );
          }
          return AppContent(
            child: RefreshIndicator(
              onRefresh: controller.load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: controller.accounts.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (BuildContext context, int index) {
                  final Account account = controller.accounts[index];
                  final Decimal balance =
                      controller.balances[account.id] ?? account.openingBalance;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Icon(
                          accountTypeIcon(account.type),
                          color: Theme.of(context).colorScheme.primary,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        account.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${accountTypeLabel(account.type)} · opening '
                        '${AppFormatters.money(account.openingBalance)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: MoneyText(
                        balance,
                        flow: MoneyFlow.neutral,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => Get.toNamed<void>(
                        AppRoutes.accountDetail,
                        arguments: account.id,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }),
      ),
      floatingActionButton: const FloatingActionButton.extended(
        onPressed: openAddAccount,
        icon: Icon(Icons.add),
        label: Text('Add account'),
      ),
    );
  }
}
