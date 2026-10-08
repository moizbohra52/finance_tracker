import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_bottom_sheet_dropdown.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> showTransactionFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext _) => const _FilterSheet(),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  final TransactionController _controller = Get.find<TransactionController>();
  late TransactionType? _type = _controller.typeFilter.value;
  late String? _accountId = _controller.accountFilter.value;
  late String? _categoryId = _controller.categoryFilter.value;
  late DateTimeRange? _range = _controller.rangeFilter.value;

  Future<void> _pickRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _apply() {
    _controller.applyFilters(
      type: _type,
      accountId: _accountId,
      categoryId: _categoryId,
      range: _range,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Account> accounts = _controller.accounts.toList();
    final List<Category> categories = _type == null
        ? _controller.categories.toList()
        : _controller.categoriesFor(_type!);
    // A category chosen for the other type no longer applies.
    final String? categoryValue =
        categories.any((Category c) => c.id == _categoryId)
        ? _categoryId
        : null;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Filter transactions', style: text.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Text('Type', style: text.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('All'),
                  selected: _type == null,
                  onSelected: (_) => setState(() => _type = null),
                ),
                ChoiceChip(
                  label: const Text('Income'),
                  selected: _type == TransactionType.income,
                  onSelected: (_) =>
                      setState(() => _type = TransactionType.income),
                ),
                ChoiceChip(
                  label: const Text('Expense'),
                  selected: _type == TransactionType.expense,
                  onSelected: (_) =>
                      setState(() => _type = TransactionType.expense),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            BottomSheetDropdown<String>(
              value: _accountId ?? '',
              options: <String>['', for (final Account a in accounts) a.id],
              labelOf: (String id) => id.isEmpty
                  ? 'All accounts'
                  : accounts.firstWhere((Account a) => a.id == id).name,
              decoration: const InputDecoration(labelText: 'Account'),
              onChanged: (String? v) =>
                  setState(() => _accountId = (v?.isEmpty ?? true) ? null : v),
            ),
            const SizedBox(height: AppSpacing.md),
            BottomSheetDropdown<String>(
              key: ValueKey<TransactionType?>(_type),
              value: categoryValue ?? '',
              options: <String>['', for (final Category c in categories) c.id],
              labelOf: (String id) => id.isEmpty
                  ? 'All categories'
                  : categories.firstWhere((Category c) => c.id == id).name,
              decoration: const InputDecoration(labelText: 'Category'),
              onChanged: (String? v) =>
                  setState(() => _categoryId = (v?.isEmpty ?? true) ? null : v),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                _range == null
                    ? 'Any date'
                    : '${AppFormatters.date(_range!.start)} – '
                          '${AppFormatters.date(_range!.end)}',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppButton(
                    label: 'Reset',
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      _controller.clearFilters();
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(label: 'Apply', onPressed: _apply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
