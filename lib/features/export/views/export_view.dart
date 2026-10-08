// ignore_for_file: deprecated_member_use
import 'package:finance_tracker/core/services/export_service.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_bottom_sheet_dropdown.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/export/controllers/export_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ExportView extends GetView<ExportController> {
  const ExportView({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      appBar: const AppAppBar(title: 'Export Data'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxPageWidth,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: <Widget>[
              // Section 1: Choose What to Export
              Text(
                'What would you like to export?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Obx(() => _buildScopeSelector(context)),

              const SizedBox(height: AppSpacing.lg),

              // Section 2: Choose File Format
              Text(
                'Choose Export Format',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Obx(() => _buildFormatSelector(context)),

              const SizedBox(height: AppSpacing.lg),

              // Section 3: Filters (Transactions and Full Report)
              Obx(() {
                final ExportType scope = controller.selectedType.value;
                if (scope != ExportType.transactions &&
                    scope != ExportType.fullReport) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Filter Options',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildFiltersCard(context),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                );
              }),

              // Export Action Card / Button
              Obx(() {
                final bool exporting = controller.isExporting.value;
                final String status = controller.statusMessage.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (exporting && status.isNotEmpty) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: <Widget>[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                status,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    FilledButton.icon(
                      onPressed: exporting ? null : controller.exportAndShare,
                      icon: exporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.share_outlined),
                      label: Text(
                        exporting
                            ? 'Exporting...'
                            : 'Export & Share (${controller.selectedFormat.value.name.toUpperCase()})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopeSelector(BuildContext context) {
    final ExportType current = controller.selectedType.value;

    final List<
      ({ExportType type, String title, String subtitle, IconData icon})
    >
    items = <({ExportType type, String title, String subtitle, IconData icon})>[
      (
        type: ExportType.transactions,
        title: 'Transactions',
        subtitle: 'Income, expense, and transfer records',
        icon: Icons.receipt_long_outlined,
      ),
      (
        type: ExportType.accounts,
        title: 'Accounts',
        subtitle: 'Account balances and summary',
        icon: Icons.account_balance_outlined,
      ),
      (
        type: ExportType.contacts,
        title: 'Khata Contacts',
        subtitle: 'Digital khata party list & net balances',
        icon: Icons.contacts_outlined,
      ),
      (
        type: ExportType.contactTransactions,
        title: 'Khata Transactions',
        subtitle: 'Credit, debit, and payment history',
        icon: Icons.swap_horiz_outlined,
      ),
      (
        type: ExportType.budgets,
        title: 'Budgets',
        subtitle: 'Monthly and custom spending limits',
        icon: Icons.pie_chart_outline_rounded,
      ),
      (
        type: ExportType.fullReport,
        title: 'Full Financial Report',
        subtitle: 'Combined summary across all records',
        icon: Icons.assessment_outlined,
      ),
    ];

    return AppCard(
      child: Column(
        children: items.map((item) {
          final bool isSelected = current == item.type;
          return RadioListTile<ExportType>(
            value: item.type,
            groupValue: current,
            onChanged: (ExportType? val) {
              if (val != null) controller.selectedType.value = val;
            },
            secondary: Icon(
              item.icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(
              item.title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(item.subtitle),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFormatSelector(BuildContext context) {
    final ExportFormat current = controller.selectedFormat.value;

    final List<
      ({
        ExportFormat format,
        String name,
        String ext,
        IconData icon,
        String desc,
      })
    >
    formats =
        <
          ({
            ExportFormat format,
            String name,
            String ext,
            IconData icon,
            String desc,
          })
        >[
          (
            format: ExportFormat.csv,
            name: 'CSV',
            ext: '.csv',
            icon: Icons.table_chart_outlined,
            desc: 'Comma-separated values, opens in Excel & Google Sheets',
          ),
          (
            format: ExportFormat.excel,
            name: 'Excel',
            ext: '.xlsx',
            icon: Icons.grid_on_outlined,
            desc: 'Formatted spreadsheet with styled headers and totals',
          ),
          (
            format: ExportFormat.pdf,
            name: 'PDF',
            ext: '.pdf',
            icon: Icons.picture_as_pdf_outlined,
            desc: 'Clean, professional report suitable for sharing & printing',
          ),
        ];

    return Row(
      children: formats.map((item) {
        final bool isSelected = current == item.format;
        final ColorScheme colors = Theme.of(context).colorScheme;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => controller.selectedFormat.value = item.format,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isSelected ? colors.primary : colors.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                  color: isSelected
                      ? colors.primaryContainer.withAlpha(50)
                      : colors.surface,
                ),
                child: Column(
                  children: <Widget>[
                    Icon(
                      item.icon,
                      size: 28,
                      color: isSelected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.name,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: isSelected ? colors.primary : colors.onSurface,
                      ),
                    ),
                    Text(
                      item.ext,
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFiltersCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Date Range Preset
          Text('Date Range', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: DateRangePreset.values.map((preset) {
              final bool isSelected = controller.datePreset.value == preset;
              return ChoiceChip(
                label: Text(preset.label),
                selected: isSelected,
                onSelected: (bool selected) async {
                  if (selected) {
                    if (preset == DateRangePreset.custom) {
                      final DateTimeRange? picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        initialDateRange: DateTimeRange(
                          start:
                              controller.customStartDate.value ??
                              DateTime.now().subtract(const Duration(days: 30)),
                          end: controller.customEndDate.value ?? DateTime.now(),
                        ),
                      );
                      if (picked != null) {
                        controller.setCustomRange(picked.start, picked.end);
                      }
                    } else {
                      controller.datePreset.value = preset;
                    }
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Selected: ${controller.dateRangeLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),

          const Divider(height: AppSpacing.xl),

          // Account Filter
          BottomSheetDropdown<String?>(
            value: controller.selectedAccountId.value,
            options: <String?>[
              null,
              ...controller.accounts.map((Account a) => a.id),
            ],
            labelOf: (String? id) {
              if (id == null) return 'All Accounts';
              final Account? acc = controller.accounts.firstWhereOrNull(
                (Account a) => a.id == id,
              );
              return acc?.name ?? id;
            },
            onChanged: (String? val) {
              controller.selectedAccountId.value = val;
            },
            decoration: const InputDecoration(
              labelText: 'Filter by Account',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Category Filter
          BottomSheetDropdown<String?>(
            value: controller.selectedCategoryId.value,
            options: <String?>[
              null,
              ...controller.categories.map((Category c) => c.id),
            ],
            labelOf: (String? id) {
              if (id == null) return 'All Categories';
              final Category? cat = controller.categories.firstWhereOrNull(
                (Category c) => c.id == id,
              );
              return cat?.name ?? id;
            },
            onChanged: (String? val) {
              controller.selectedCategoryId.value = val;
            },
            decoration: const InputDecoration(
              labelText: 'Filter by Category',
              prefixIcon: Icon(Icons.category_outlined),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Transaction Type Filter
          BottomSheetDropdown<TransactionType?>(
            value: controller.selectedTxType.value,
            options: const <TransactionType?>[
              null,
              TransactionType.income,
              TransactionType.expense,
              TransactionType.transfer_in,
              TransactionType.transfer_out,
            ],
            labelOf: (TransactionType? type) {
              if (type == null) return 'All Types';
              switch (type) {
                case TransactionType.income:
                  return 'Income';
                case TransactionType.expense:
                  return 'Expense';
                case TransactionType.transfer_in:
                  return 'Transfer In';
                case TransactionType.transfer_out:
                  return 'Transfer Out';
                default:
                  return type.name;
              }
            },
            onChanged: (TransactionType? val) {
              controller.selectedTxType.value = val;
            },
            decoration: const InputDecoration(
              labelText: 'Filter by Transaction Type',
              prefixIcon: Icon(Icons.filter_list_outlined),
            ),
          ),
        ],
      ),
    );
  }
}
