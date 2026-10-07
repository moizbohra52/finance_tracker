import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/account_transaction_summary.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/features/accounts/controllers/account_detail_controller.dart';
import 'package:finance_tracker/features/accounts/views/account_list_view.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AccountDetailView extends GetView<AccountDetailController> {
  const AccountDetailView({super.key});

  Future<void> _delete(BuildContext context, Account account) async {
    final AccountController accounts = Get.find<AccountController>();
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete ${account.name}?',
      message:
          'The account is removed from your balances. Its past transactions '
          'are kept in your history.',
    );
    if (!confirmed) return;
    if (await accounts.deleteAccount(account.id)) {
      AppSnackbar.show('Account deleted');
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final Account? account = controller.account.value;
      return Scaffold(
        appBar: AppAppBar(title: account?.name ?? 'Account'),
        body: SafeArea(child: _body(context, account)),
      );
    });
  }

  Widget _body(BuildContext context, Account? account) {
    if (controller.isLoading.value) {
      return const LoadingState(message: 'Loading account');
    }
    final String? error = controller.error.value;
    if (error != null) {
      return ErrorState(message: error, onRetry: controller.load);
    }
    final AccountTransactionSummary? summary = controller.summary.value;
    if (account == null || summary == null) {
      return const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Account not found',
        message: 'It may have been deleted.',
      );
    }
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final TransactionController list = Get.find<TransactionController>();
    final AccountController accounts = Get.find<AccountController>();

    return AppContent(
      child: RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          children: <Widget>[
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  Icon(accountTypeIcon(account.type), size: 32),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Current balance', style: text.labelLarge),
                  Text(
                    AppFormatters.money(summary.balance),
                    style: text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Opening balance ${AppFormatters.money(account.openingBalance)}'
                    '${account.openingBalanceDate == null ? '' : ' on ${AppFormatters.date(account.openingBalanceDate!)}'}',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: SummaryTile(
                    icon: Icons.south_west_rounded,
                    label: 'Total income',
                    value: AppFormatters.money(summary.totalIncome),
                    color: money.income,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SummaryTile(
                    icon: Icons.north_east_rounded,
                    label: 'Total expense',
                    value: AppFormatters.money(summary.totalExpense),
                    color: money.expense,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Recent activity'),
            const SizedBox(height: AppSpacing.sm),
            if (controller.recent.isEmpty)
              const AppCard(
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message: 'Income and expenses for this account show here.',
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  children: <Widget>[
                    for (final Transaction t in controller.recent)
                      TransactionListItem(
                        transaction: t,
                        title:
                            list.categoryOf(t.categoryId)?.name ?? t.type.name,
                        iconKey: list.categoryOf(t.categoryId)?.icon,
                        subtitle: account.name,
                        onTap: () => Get.toNamed<void>(
                          AppRoutes.transactionDetail,
                          arguments: t.id,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            Obx(() {
              final String? deleteError = accounts.deletion.error.value;
              return deleteError == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: InlineMessage(message: deleteError),
                    );
            }),
            AppButton(
              label: 'Edit account & opening balance',
              icon: Icons.edit_outlined,
              onPressed: () =>
                  Get.toNamed<void>(AppRoutes.accountForm, arguments: account),
            ),
            const SizedBox(height: AppSpacing.md),
            Obx(
              () => AppButton(
                label: 'Delete account',
                icon: Icons.delete_outline,
                variant: AppButtonVariant.destructive,
                isLoading: accounts.deletion.isBusy.value,
                onPressed: () => _delete(context, account),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
