import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/features/savings/controllers/savings_goal_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Add a savings goal, or edit the [SavingsGoal] passed as the route argument.
class SavingsGoalFormView extends StatefulWidget {
  const SavingsGoalFormView({super.key});

  @override
  State<SavingsGoalFormView> createState() => _SavingsGoalFormViewState();
}

class _SavingsGoalFormViewState extends State<SavingsGoalFormView> {
  final SavingsGoalController _controller = Get.find<SavingsGoalController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _target = TextEditingController();
  final TextEditingController _saved = TextEditingController(text: '0');

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = SavingsGoalController.newId();
  late final SavingsGoal? _existing;
  DateTime? _targetDate;

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    _existing = args is SavingsGoal ? args : null;
    final SavingsGoal? g = _existing;
    if (g != null) {
      _name.text = g.name;
      _target.text = g.targetAmount.toString();
      _saved.text = g.savedAmount.toString();
      _targetDate = g.targetDate;
    }
    _controller.save.error.value = null;
    _controller.deletion.error.value = null;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool saved = await _controller.saveGoal(
      id: _existing?.id ?? _id,
      existing: _existing,
      name: _name.text,
      targetAmount: Decimal.parse(_target.text.trim()),
      savedAmount: Decimal.parse(_saved.text.trim()),
      targetDate: _targetDate,
    );
    if (!saved) return;
    AppSnackbar.show(
      _existing == null ? 'Savings goal added'.tr : 'Savings goal updated'.tr,
    );
    Get.back<void>();
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this savings goal?'.tr,
      message: 'Your transactions are not affected.'.tr,
    );
    if (!confirmed) return;
    if (await _controller.deleteGoal(_existing!.id)) {
      AppSnackbar.show('Savings goal deleted'.tr);
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = _existing != null;
    final DateTime now = DateTime.now();

    return Scaffold(
      appBar: AppAppBar(
        title: editing ? 'Edit savings goal'.tr : 'Add savings goal'.tr,
      ),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 120,
          child: Form(
            key: _formKey,
            child: ListView(
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xxl,
              ),
              children: <Widget>[
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  label: 'Goal name'.tr,
                  hintText: 'e.g. New phone, Emergency fund'.tr,
                  controller: _name,
                  autofocus: !editing,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      Validators.name(v, 'a goal name'.tr),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Target amount'.tr,
                  controller: _target,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: Validators.positiveAmount,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Saved so far'.tr,
                  controller: _saved,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: Validators.nonNegativeAmount,
                ),
                const SizedBox(height: AppSpacing.md),
                AppDateField(
                  label: 'Target date (optional)'.tr,
                  value: _targetDate,
                  firstDate: _targetDate != null && _targetDate!.isBefore(now)
                      ? _targetDate
                      : DateTime(now.year, now.month, now.day),
                  lastDate: DateTime(now.year + 30),
                  onChanged: (DateTime d) => setState(() => _targetDate = d),
                  onCleared: () => setState(() => _targetDate = null),
                ),
                const SizedBox(height: AppSpacing.lg),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: editing ? 'Save changes'.tr : 'Add savings goal'.tr,
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
                      label: 'Delete savings goal'.tr,
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
