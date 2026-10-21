import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/data/repositories/receipt_store.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_detail_controller.dart';
import 'package:finance_tracker/features/transactions/widgets/receipt_preview.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TransactionDetailView extends GetView<TransactionDetailController> {
  const TransactionDetailView({super.key, required this.id});

  /// Tag of this screen's controller (see routeIdArgument).
  final String id;

  @override
  String get tag => id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: 'Transaction'.tr),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return LoadingState(message: 'Loading transaction'.tr);
          }
          final String? error = controller.error.value;
          if (error != null) {
            return ErrorState(message: error, onRetry: controller.load);
          }
          final Transaction? t = controller.transaction.value;
          if (t == null) {
            return EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Transaction not found'.tr,
              message: 'It may have been deleted.'.tr,
            );
          }
          return _Details(transaction: t, transfer: controller.transfer.value);
        }),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.transaction, this.transfer});

  final Transaction transaction;

  /// Both legs when [transaction] is part of a transfer.
  final TransferLegs? transfer;

  bool get _editable =>
      transfer != null ||
      transaction.type == TransactionType.income ||
      transaction.type == TransactionType.expense;

  Future<void> _delete(BuildContext context) async {
    final TransactionController list = Get.find<TransactionController>();
    final TransferLegs? transfer = this.transfer;
    final String amount = AppFormatters.money(transaction.amount);
    final bool confirmed = await confirmDestructive(
      context,
      title: transfer == null
          ? 'Delete transaction?'.tr
          : 'Delete transfer?'.tr,
      message: transfer == null
          ? 'This @type of @amount will be removed from your balance.'.trParams(
              <String, String>{
                'type': transaction.type.label.toLowerCase(),
                'amount': amount,
              },
            )
          : 'This transfer of @amount from @from to @to will be removed from both accounts.'
                .trParams(<String, String>{
                  'amount': amount,
                  'from': list.accountName(transfer.fromAccountId),
                  'to': list.accountName(transfer.toAccountId),
                }),
    );
    if (!confirmed) return;
    final bool deleted = transfer == null
        ? await list.deleteTransaction(transaction.id)
        : await list.deleteTransfer(transfer.transferId);
    if (deleted) {
      AppSnackbar.show(
        transfer == null ? 'Transaction deleted'.tr : 'Transfer deleted'.tr,
      );
      Get.back<void>();
    }
  }

  void _edit() {
    final TransferLegs? transfer = this.transfer;
    if (transfer != null) {
      Get.toNamed<void>(
        AppRoutes.transferForm,
        arguments: TransferFormArgs(transferId: transfer.transferId),
      );
      return;
    }
    Get.toNamed<void>(
      AppRoutes.transactionForm,
      arguments: TransactionFormArgs(
        type: transaction.type,
        existing: transaction,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TransactionController list = Get.find<TransactionController>();
    final TextTheme text = Theme.of(context).textTheme;
    final category = list.categoryOf(transaction.categoryId);
    final String? note = transaction.note ?? transaction.description;
    final TransferLegs? transfer = this.transfer;

    return AppContent(
      child: ListView(
        children: <Widget>[
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: <Widget>[
                IconBadge(
                  icon: CategoryIcons.of(category?.icon, transaction.type),
                  size: AppSizes.iconLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                // A transfer moves money between the user's own accounts,
                // so it is shown without a sign or money colour.
                MoneyText(
                  transaction.amount,
                  flow: transfer != null
                      ? MoneyFlow.neutral
                      : transaction.type.isInflow
                      ? MoneyFlow.inflow
                      : MoneyFlow.outflow,
                  style: text.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  transfer != null ? 'Transfer'.tr : transaction.type.label,
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                if (transfer != null) ...<Widget>[
                  _Row('From'.tr, list.accountName(transfer.fromAccountId)),
                  _Row('To'.tr, list.accountName(transfer.toAccountId)),
                ] else ...<Widget>[
                  _Row(
                    'Category'.tr,
                    category?.name ??
                        (transaction.type == TransactionType.opening_balance
                            ? 'Opening Balance'.tr
                            : 'Uncategorised'.tr),
                  ),
                  _Row('Account'.tr, list.accountName(transaction.accountId)),
                ],
                _Row(
                  'Date'.tr,
                  AppFormatters.dateTime(transaction.transactionDate),
                ),
                if (note != null && note.isNotEmpty) _Row('Note'.tr, note),
                // Shows nothing when there is no receipt.
                if (transfer == null && Get.isRegistered<ReceiptStore>())
                  ReceiptPreview(transaction: transaction),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Obx(() {
            final String? error = list.deletion.error.value;
            return error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: InlineMessage(message: error),
                  );
          }),
          if (_editable)
            AppButton(
              label: 'Edit'.tr,
              icon: Icons.edit_outlined,
              onPressed: _edit,
            ),
          if (_editable) const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Remind me'.tr,
            icon: Icons.alarm_add_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => Get.toNamed<void>(
              AppRoutes.reminderForm,
              arguments: ReminderFormArgs(
                type: ReminderType.payment,
                transactionId: transaction.id,
                amount: transaction.amount,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => AppButton(
              label: 'Delete'.tr,
              icon: Icons.delete_outline,
              variant: AppButtonVariant.destructive,
              isLoading: list.deletion.isBusy.value,
              onPressed: () => _delete(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 96, child: Text(label, style: text.bodyMedium)),
          Expanded(child: Text(value, style: text.titleSmall)),
        ],
      ),
    );
  }
}
