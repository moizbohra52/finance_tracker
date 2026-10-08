import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_bottom_sheet_dropdown.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/features/budgets/controllers/budget_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Add a budget, or edit the [Budget] passed as the route argument.
class BudgetFormView extends StatefulWidget {
  const BudgetFormView({super.key});

  @override
  State<BudgetFormView> createState() => _BudgetFormViewState();
}

class _BudgetFormViewState extends State<BudgetFormView> {
  final BudgetController _controller = Get.find<BudgetController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = BudgetController.newId();
  late final Budget? _existing;
  String? _categoryId;
  BudgetPeriodType _periodType = BudgetPeriodType.monthly;
  late DateTime _start;
  DateTime? _end;
  bool _alert75 = true;
  bool _alert90 = true;
  bool _alert100 = true;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    _existing = args is Budget ? args : null;
    final DateTime now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    final Budget? b = _existing;
    if (b != null) {
      _amount.text = b.amount.toString();
      _categoryId = b.categoryId;
      _periodType = b.periodType;
      _start = b.startDate;
      _end = b.endDate;
      _alert75 = b.alert75;
      _alert90 = b.alert90;
      _alert100 = b.alert100;
    }
    _controller.save.error.value = null;
    _controller.deletion.error.value = null;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bool valid = _formKey.currentState?.validate() ?? false;
    String? dateError;
    if (_periodType == BudgetPeriodType.custom) {
      if (_end == null) {
        dateError = 'Choose an end date';
      } else if (_end!.isBefore(_start)) {
        dateError = 'The end date must not be before the start date';
      }
    }
    setState(() => _dateError = dateError);
    if (!valid || dateError != null) return;
    final bool saved = await _controller.saveBudget(
      id: _existing?.id ?? _id,
      existing: _existing,
      categoryId: _categoryId,
      amount: Decimal.parse(_amount.text.trim()),
      periodType: _periodType,
      startDate: _start,
      endDate: _end,
      alert75: _alert75,
      alert90: _alert90,
      alert100: _alert100,
    );
    if (!saved) return;
    AppSnackbar.show(_existing == null ? 'Budget added' : 'Budget updated');
    Get.back<void>();
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this budget?',
      message: 'Your transactions are not affected.',
    );
    if (!confirmed) return;
    if (await _controller.deleteBudget(_existing!.id)) {
      AppSnackbar.show('Budget deleted');
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = _existing != null;
    final TextTheme text = Theme.of(context).textTheme;
    final bool custom = _periodType == BudgetPeriodType.custom;
    final List<Category> categories = _controller.expenseCategories;
    final String? categoryValue =
        categories.any((Category c) => c.id == _categoryId)
        ? _categoryId
        : null;

    return Scaffold(
      appBar: AppAppBar(title: editing ? 'Edit budget' : 'Add budget'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 120,
          child: Form(
            key: _formKey,
            child: ListView(
              children: <Widget>[
                BottomSheetDropdown<String>(
                  value: categoryValue ?? '',
                  options: <String>[
                    '',
                    for (final Category c in categories) c.id,
                  ],
                  labelOf: (String id) => id.isEmpty
                      ? 'All expenses'
                      : categories
                            .firstWhere((Category c) => c.id == id)
                            .name,
                  decoration: const InputDecoration(labelText: 'Applies to'),
                  onChanged: (String? v) =>
                      setState(() => _categoryId = (v?.isEmpty ?? true) ? null : v),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Budget amount',
                  controller: _amount,
                  autofocus: !editing,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: Validators.positiveAmount,
                ),
                const SizedBox(height: AppSpacing.lg),
                SegmentedButton<BudgetPeriodType>(
                  segments: const <ButtonSegment<BudgetPeriodType>>[
                    ButtonSegment<BudgetPeriodType>(
                      value: BudgetPeriodType.monthly,
                      icon: Icon(Icons.calendar_month_outlined),
                      label: Text('Monthly'),
                    ),
                    ButtonSegment<BudgetPeriodType>(
                      value: BudgetPeriodType.custom,
                      icon: Icon(Icons.date_range_outlined),
                      label: Text('Custom'),
                    ),
                  ],
                  selected: <BudgetPeriodType>{_periodType},
                  onSelectionChanged: (Set<BudgetPeriodType> s) =>
                      setState(() => _periodType = s.first),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  custom
                      ? 'One fixed period with a start and an end date.'
                      : 'Repeats every calendar month from the start month.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                AppDateField(
                  label: custom ? 'Start date' : 'Starts',
                  value: _start,
                  onChanged: (DateTime d) => setState(() => _start = d),
                ),
                if (custom) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  AppDateField(
                    label: 'End date',
                    value: _end,
                    onChanged: (DateTime d) => setState(() => _end = d),
                  ),
                ],
                if (_dateError != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _dateError!,
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text('Alert me at', style: text.titleSmall),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('75% spent'),
                  value: _alert75,
                  onChanged: (bool v) => setState(() => _alert75 = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('90% spent'),
                  value: _alert90,
                  onChanged: (bool v) => setState(() => _alert90 = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('100% spent (over budget)'),
                  value: _alert100,
                  onChanged: (bool v) => setState(() => _alert100 = v),
                ),
                const SizedBox(height: AppSpacing.lg),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: editing ? 'Save changes' : 'Add budget',
                    icon: Icons.check_rounded,
                    isLoading: _controller.save.isBusy.value,
                    onPressed: _submit,
                  ),
                ),
                if (editing) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  SubmitErrorMessage(_controller.deletion),
                  Obx(
                    () => AppButton(
                      label: 'Delete budget',
                      icon: Icons.delete_outline,
                      variant: AppButtonVariant.destructive,
                      isLoading: _controller.deletion.isBusy.value,
                      onPressed: _delete,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
