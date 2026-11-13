import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/core/widgets/swipe_to_delete.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/account_transaction_summary.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/features/accounts/controllers/account_detail_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/views/delete_transaction.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/account_list_item.dart';
import 'package:finance_tracker/widgets/transaction_day_header.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AccountDetailView extends GetView<AccountDetailController> {
  const AccountDetailView({super.key, required this.id});

  /// Tag of this screen's controller (see routeIdArgument).
  final String id;

  @override
  String get tag => id;

  Future<void> _delete(BuildContext context, Account account) async {
    final AccountController accounts = Get.find<AccountController>();
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete @name?'.trParams(<String, String>{'name': account.name}),
      message:
          'The account is removed from your balances. Its past transactions are kept in your history.'
              .tr,
    );
    if (!confirmed) return;
    if (await accounts.deleteAccount(account.id)) {
      AppSnackbar.show('Account deleted'.tr);
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final Account? account = controller.account.value;
      return Scaffold(
        appBar: AppAppBar(
          title: account?.name ?? 'Account'.tr,
          // In the bar, not under the list: the list now has no end.
          actions: <Widget>[
            if (account != null) ...<Widget>[
              IconButton(
                tooltip: 'Transfer money'.tr,
                icon: const Icon(Icons.swap_horiz_rounded),
                onPressed: () => Get.toNamed<void>(
                  AppRoutes.transferForm,
                  arguments: TransferFormArgs(fromAccountId: account.id),
                ),
              ),
              IconButton(
                tooltip: 'Edit account & opening balance'.tr,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Get.toNamed<void>(
                  AppRoutes.accountForm,
                  arguments: account,
                ),
              ),
              IconButton(
                tooltip: 'Delete account'.tr,
                icon: const Icon(Icons.delete_outline),
                color: Theme.of(context).colorScheme.error,
                onPressed: Get.find<AccountController>().deletion.isBusy.value
                    ? null
                    : () => _delete(context, account),
              ),
            ],
          ],
        ),
        body: SafeArea(child: _body(context, account)),
      );
    });
  }

  Widget _body(BuildContext context, Account? account) {
    if (controller.isLoading.value) {
      return LoadingState(message: 'Loading account'.tr);
    }
    final String? error = controller.error.value;
    if (error != null) {
      return ErrorState(message: error, onRetry: controller.load);
    }
    final AccountTransactionSummary? summary = controller.summary.value;
    if (account == null || summary == null) {
      return EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Account not found'.tr,
        message: 'It may have been deleted.'.tr,
      );
    }
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final TransactionController list = Get.find<TransactionController>();
    final AccountController accounts = Get.find<AccountController>();

    // Grouped by day like the Transactions tab: a row shows only its time.
    final List<TransactionListRow> rows = groupTransactionsByDay(
      controller.items,
    );
    final bool loadingMore = controller.isLoadingMore.value;
    // Rows are built lazily, outside the Obx, so subscribe here to the
    // lookups they read; else rows built before the lookups load stay bare.
    list.categoryIndex.length;
    list.accounts.length;

    final Widget header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: <Widget>[
              IconBadge(
                icon: accountTypeIcon(account.type),
                size: AppSizes.iconLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Current balance'.tr, style: text.labelLarge),
              CountUpMoney(
                summary.balance,
                style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                account.openingBalanceDate == null
                    ? 'Opening balance @amount'.trParams(<String, String>{
                        'amount': AppFormatters.money(account.openingBalance),
                      })
                    : 'Opening balance @amount on @date'.trParams(<
                        String,
                        String
                      >{
                        'amount': AppFormatters.money(account.openingBalance),
                        'date': AppFormatters.date(account.openingBalanceDate!),
                      }),
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
                label: 'Money in'.tr,
                value: AppFormatters.money(summary.totalIncome),
                color: money.income,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SummaryTile(
                icon: Icons.north_east_rounded,
                label: 'Money out'.tr,
                value: AppFormatters.money(summary.totalExpense),
                color: money.expense,
              ),
            ),
          ],
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
        SectionHeader(title: 'All transactions'.tr),
        // The first day header brings its own space above.
        if (rows.isEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet'.tr,
              message: 'Income and expenses for this account show here.'.tr,
            ),
          ),
        ],
      ],
    );

    return AppContent(
      child: RefreshIndicator(
        onRefresh: controller.load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) {
            if (n.metrics.extentAfter < 300) controller.loadMore();
            return false;
          },
          // Header, the day headers and transactions, then the loading footer.
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: rows.length + 2,
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) return header;
              if (index > rows.length) {
                return loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : const SizedBox(height: AppSpacing.lg);
              }
              return switch (rows[index - 1]) {
                TransactionDayRow(:final String label, :final int count) =>
                  TransactionDayHeader(label: label, count: count),
                TransactionItemRow(transaction: final Transaction t) =>
                  SwipeToDelete(
                    key: ValueKey<String>(t.id),
                    // A row made by a split group is changed in the group.
                    enabled: !t.isSplitDerived && !t.isLoanDerived,
                    margin: TransactionListItem.cardMargin,
                    onDelete: () => swipeDeleteTransaction(context, t),
                    onDismissed: () => controller.items.removeWhere(
                      (Transaction x) => x.id == t.id,
                    ),
                    child: TransactionListItem(
                      padding: AppListTile.flatPadding,
                      transaction: t,
                      // This list holds one account's rows, so a transfer's
                      // other leg is looked up in the full list.
                      title: TransactionListItem.titleFor(
                        t,
                        categoryName: list.categoryOf(t.categoryId)?.name,
                        nearby: list.items,
                        accountName: list.accountName,
                      ),
                      iconKey: list.categoryOf(t.categoryId)?.icon,
                      subtitle: account.name,
                      onTap: () => Get.toNamed<void>(
                        AppRoutes.transactionDetail,
                        arguments: t.id,
                      ),
                    ),
                  ),
              };
            },
          ),
        ),
      ),
    );
  }
}
