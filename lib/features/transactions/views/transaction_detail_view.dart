import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_detail_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TransactionDetailView extends GetView<TransactionDetailController> {
  const TransactionDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Transaction'),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const LoadingState(message: 'Loading transaction');
          }
          final String? error = controller.error.value;
          if (error != null) {
            return ErrorState(message: error, onRetry: controller.load);
          }
          final Transaction? t = controller.transaction.value;
          if (t == null) {
            return const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Transaction not found',
              message: 'It may have been deleted.',
            );
          }
          return _Details(transaction: t);
        }),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.transaction});

  final Transaction transaction;

  bool get _editable =>
      transaction.type == TransactionType.income ||
      transaction.type == TransactionType.expense;

  Future<void> _delete(BuildContext context) async {
    final TransactionController list = Get.find<TransactionController>();
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete transaction?',
      message:
          'This ${transaction.type.label.toLowerCase()} of '
          '${AppFormatters.money(transaction.amount)} will be removed from '
          'your balance.',
    );
    if (!confirmed) return;
    if (await list.deleteTransaction(transaction.id)) {
      AppSnackbar.show('Transaction deleted');
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TransactionController list = Get.find<TransactionController>();
    final TextTheme text = Theme.of(context).textTheme;
    final category = list.categoryOf(transaction.categoryId);
    final String? note = transaction.note ?? transaction.description;

    return AppContent(
      child: ListView(
        children: <Widget>[
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: <Widget>[
                CircleAvatar(
                  radius: 28,
                  child: Icon(
                    CategoryIcons.of(category?.icon, transaction.type),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                MoneyText(
                  transaction.amount,
                  flow: transaction.type.isInflow
                      ? MoneyFlow.inflow
                      : MoneyFlow.outflow,
                  style: text.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(transaction.type.label, style: text.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                _Row('Category', category?.name ?? 'Uncategorised'),
                _Row('Account', list.accountName(transaction.accountId)),
                _Row(
                  'Date',
                  AppFormatters.dateTime(transaction.transactionDate),
                ),
                if (note != null && note.isNotEmpty) _Row('Note', note),
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
              label: 'Edit',
              icon: Icons.edit_outlined,
              onPressed: () => Get.toNamed<void>(
                AppRoutes.transactionForm,
                arguments: TransactionFormArgs(
                  type: transaction.type,
                  existing: transaction,
                ),
              ),
            ),
          if (_editable) const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Remind me',
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
              label: 'Delete',
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
