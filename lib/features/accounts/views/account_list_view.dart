import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/account_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
            return const AppContent(
              child: SkeletonList(count: 4, type: SkeletonType.account),
            );
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
                padding: const EdgeInsets.only(bottom: AppSpacing.fabClearance),
                itemCount: controller.accounts.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (BuildContext context, int index) {
                  final Account account = controller.accounts[index];
                  final Decimal balance =
                      controller.balances[account.id] ?? account.openingBalance;
                  return AppCard(
                    padding: EdgeInsets.zero,
                    child: AccountTile(
                      account: account,
                      balance: balance,
                      subtitle:
                          '${accountTypeLabel(account.type)} · opening '
                          '${AppFormatters.money(account.openingBalance)}',
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
