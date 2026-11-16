import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_bottom_sheet_dropdown.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/statement_import.dart';
import 'package:finance_tracker/features/import/controllers/import_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Import transactions from a CSV or Excel file: choose the file, check which
/// column holds what, see what will be added, import.
class ImportView extends GetView<ImportController> {
  const ImportView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: 'Import transactions'.tr),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxPageWidth,
          child: Obx(() {
            if (controller.isLoading.value) return const LoadingState();
            final String? error = controller.loadError.value;
            if (error != null) {
              return ErrorState(message: error, onRetry: controller.load);
            }
            if (controller.accounts.isEmpty) {
              return EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Add an account first'.tr,
                message: 'Imported entries go into one of your accounts.'.tr,
                actionLabel: 'Add account'.tr,
                onAction: () async {
                  await Get.toNamed<void>(AppRoutes.accountForm);
                  await controller.load();
                },
              );
            }
            return ListView(
              children: <Widget>[
                const _FileCard(),
                if (controller.table.value != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  SectionHeader(title: 'Columns'.tr),
                  const SizedBox(height: AppSpacing.sm),
                  const _ColumnsCard(),
                  const _Preview(),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _FileCard extends GetView<ImportController> {
  const _FileCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Obx(() {
        final String? name = controller.fileName.value;
        final ImportTable? table = controller.table.value;
        final String? error = controller.fileError.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppListTile(
              padding: EdgeInsets.zero,
              leading: const IconBadge(icon: Icons.upload_file_outlined),
              title: name ?? 'Import from a file'.tr,
              subtitle: table == null
                  ? 'CSV or Excel (.xlsx) from your bank or another app'.tr
                  : 'Rows: @count'.trParams(<String, String>{
                      'count': '${table.rows.length}',
                    }),
              subtitleMaxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: name == null ? 'Choose file'.tr : 'Choose another file'.tr,
              icon: Icons.folder_open_outlined,
              variant: name == null
                  ? AppButtonVariant.primary
                  : AppButtonVariant.secondary,
              isLoading: controller.isReading.value,
              onPressed: controller.chooseFile,
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              InlineMessage(message: error),
            ],
            if (name == null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              InlineMessage(
                tone: InlineMessageTone.info,
                icon: Icons.info_outline_rounded,
                message:
                    'Entries already in the app are skipped, so importing the same file twice adds nothing.'
                        .tr,
                announce: false,
              ),
            ],
          ],
        );
      }),
    );
  }
}

class _ColumnsCard extends GetView<ImportController> {
  const _ColumnsCard();

  @override
  Widget build(BuildContext context) {
    final List<(ImportField, String)> fields = <(ImportField, String)>[
      (ImportField.date, 'Date'.tr),
      (ImportField.amount, 'Amount'.tr),
      (ImportField.debit, 'Debit (money out)'.tr),
      (ImportField.credit, 'Credit (money in)'.tr),
      (ImportField.type, 'Type (income or expense)'.tr),
      (ImportField.category, 'Category'.tr),
      (ImportField.note, 'Note'.tr),
      (ImportField.account, 'Account'.tr),
    ];
    return AppCard(
      child: Obx(() {
        final List<String> headers = controller.table.value?.headers ?? [];
        final List<int?> options = <int?>[
          null,
          for (int i = 0; i < headers.length; i++) i,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final (ImportField field, String label) in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: BottomSheetDropdown<int?>(
                  value: controller.columns[field],
                  options: options,
                  labelOf: (int? i) =>
                      i == null ? 'Not in file'.tr : headers[i],
                  onChanged: (int? i) => controller.setColumn(field, i),
                  decoration: InputDecoration(labelText: label),
                ),
              ),
            BottomSheetDropdown<String>(
              value: controller.accountId.value,
              options: <String>[for (final a in controller.accounts) a.id],
              labelOf: controller.accountName,
              onChanged: controller.setAccount,
              decoration: InputDecoration(
                labelText: 'Import into account'.tr,
                helperText:
                    'For rows without an account, or with one not in the app'
                        .tr,
                helperMaxLines: 2,
              ),
            ),
            if (!controller.hasRequiredColumns) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              InlineMessage(
                tone: InlineMessageTone.notice,
                message:
                    'Choose the Date column, and Amount or Debit/Credit.'.tr,
              ),
            ],
          ],
        );
      }),
    );
  }
}

class _Preview extends GetView<ImportController> {
  const _Preview();

  static const int _sampleSize = 5;

  Future<void> _import() async {
    final int count = controller.plan.value?.transactions.length ?? 0;
    if (!await controller.importNow()) return;
    Get.back<void>();
    AppSnackbar.show(
      'Entries imported: @count'.trParams(<String, String>{'count': '$count'}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ImportPlan? plan = controller.plan.value;
      if (plan == null) return const SizedBox.shrink();
      final int count = plan.transactions.length;
      final String Function(String) name = controller.accountName;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: 'Preview'.tr),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _CountLine(
                  icon: Icons.add_circle_outline_rounded,
                  text: 'New entries: @count'.trParams(<String, String>{
                    'count': '$count',
                  }),
                ),
                _CountLine(
                  icon: Icons.content_copy_rounded,
                  text: 'Already in the app, skipped: @count'.trParams(
                    <String, String>{'count': '${plan.duplicates}'},
                  ),
                ),
                _CountLine(
                  icon: Icons.help_outline_rounded,
                  text:
                      'Rows not read (totals, blank rows, transfers), skipped: @count'
                          .trParams(<String, String>{
                            'count': '${plan.unreadable}',
                          }),
                ),
              ],
            ),
          ),
          for (final MapEntry<String, ImportAccountChange> change
              in plan.accounts.entries) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _BalanceCard(accountId: change.key, change: change.value),
          ],
          if (count > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final Transaction t in plan.transactions.take(
                    _sampleSize,
                  ))
                    _sample(t, plan.transactions, name),
                  if (count > _sampleSize)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        'and @count more'.trParams(<String, String>{
                          'count': '${count - _sampleSize}',
                        }),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SubmitErrorMessage(controller.save),
          AppButton(
            label: count == 0
                ? 'Nothing new to import'.tr
                : 'Import entries (@count)'.trParams(<String, String>{
                    'count': '$count',
                  }),
            icon: Icons.download_done_rounded,
            isLoading: controller.save.isBusy.value,
            onPressed: count == 0 ? null : _import,
          ),
        ],
      );
    });
  }

  Widget _sample(
    Transaction t,
    List<Transaction> all,
    String Function(String) accountName,
  ) {
    final Category? category = controller.categoryOf(t.categoryId);
    return TransactionListItem(
      padding: AppListTile.flatPadding,
      transaction: t,
      title: TransactionListItem.titleFor(
        t,
        categoryName: category?.name,
        nearby: all,
        accountName: accountName,
      ),
      iconKey: category?.icon,
      subtitle:
          '${accountName(t.accountId)} · ${AppFormatters.date(t.transactionDate)}',
    );
  }
}

class _CountLine extends StatelessWidget {
  const _CountLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _BalanceCard extends GetView<ImportController> {
  const _BalanceCard({required this.accountId, required this.change});

  final String accountId;
  final ImportAccountChange change;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      child: Obx(() {
        final bool keep = !controller.balanceChanges.contains(accountId);
        final Decimal now = controller.balanceOf(accountId);
        final Decimal after = keep ? now : now + change.net;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(controller.accountName(accountId), style: text.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            _AmountLine(
              label: 'Balance now'.tr,
              value: AppFormatters.money(now),
            ),
            _AmountLine(
              label: 'After import'.tr,
              value: AppFormatters.money(after),
            ),
            if (change.net != Decimal.zero)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text("Keep today's balance".tr),
                subtitle: Text(
                  keep
                      ? 'Adds one adjustment entry of @amount before the imported entries'
                            .trParams(<String, String>{
                              'amount': AppFormatters.money(change.net.abs()),
                            })
                      : 'The imported entries change this balance'.tr,
                ),
                value: keep,
                onChanged: (bool v) =>
                    controller.setKeepBalance(accountId, keep: v),
              ),
          ],
        );
      }),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
