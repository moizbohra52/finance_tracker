import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/features/savings/controllers/savings_goal_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Opens the Add money sheet for [goal].
Future<void> showAddMoneySheet(BuildContext context, SavingsGoal goal) {
  Get.find<SavingsGoalController>().save.error.value = null;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AddMoneySheet(goal: goal),
  );
}

/// Amount, quick amounts and a live preview of the goal after adding.
class AddMoneySheet extends StatefulWidget {
  const AddMoneySheet({super.key, required this.goal});

  final SavingsGoal goal;

  /// Quick amounts offered under the field, in whole currency units.
  static const List<int> quickAmounts = <int>[500, 1000, 5000];

  @override
  State<AddMoneySheet> createState() => _AddMoneySheetState();
}

class _AddMoneySheetState extends State<AddMoneySheet> {
  final SavingsGoalController _controller = Get.find<SavingsGoalController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();

  // One id per sheet, so a retried save upserts the same history entry.
  final String _id = SavingsGoalController.newId();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The goal as last loaded: a sync may refresh it while the sheet is open.
  SavingsGoal get _goal => _controller.byId(widget.goal.id) ?? widget.goal;

  /// The typed amount when it is a valid one, else null.
  Decimal? get _typed {
    final String text = _amount.text.trim();
    if (Validators.positiveAmount(text) != null) return null;
    return Decimal.parse(text);
  }

  void _fill(Decimal amount) {
    _amount.text = amount.toString();
    _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
    setState(() {});
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool saved = await _controller.addMoney(
      id: _id,
      goal: _goal,
      amount: Decimal.parse(_amount.text.trim()),
    );
    if (!saved || !mounted) return;
    Navigator.of(context).pop();
    AppSnackbar.show(
      'Money added to @goal'.trParams(<String, String>{'goal': _goal.name}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final SavingsGoal goal = _goal;
    final Decimal? typed = _typed;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconBadge(
                      icon: Icons.savings_outlined,
                      color: colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Add money'.tr,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            goal.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Amount'.tr,
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  validator: Validators.positiveAmount,
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    if (!goal.isReached)
                      ActionChip(
                        avatar: const Icon(Icons.flag_outlined, size: 18),
                        label: Text(
                          '@amount left'.trParams(<String, String>{
                            'amount': AppFormatters.money(goal.remaining),
                          }),
                        ),
                        onPressed: () => _fill(goal.remaining),
                      ),
                    for (final int quick in AddMoneySheet.quickAmounts)
                      ActionChip(
                        label: Text(
                          '${AppFormatters.currencySymbol}'
                          '${AppFormatters.number(quick, decimalDigits: 0)}',
                        ),
                        onPressed: () => _fill(Decimal.fromInt(quick)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Preview(
                  before: goal,
                  after: goal.afterAdding(typed ?? Decimal.zero),
                ),
                const SizedBox(height: AppSpacing.lg),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: typed == null
                        ? 'Add money'.tr
                        : 'Add @amount'.trParams(<String, String>{
                            'amount': AppFormatters.money(typed),
                          }),
                    icon: Icons.add_rounded,
                    isLoading: _controller.save.isBusy.value,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The goal's progress after adding the typed amount; with nothing typed it
/// shows where the goal stands now.
class _Preview extends StatelessWidget {
  const _Preview({required this.before, required this.after});

  final SavingsGoal before;
  final SavingsGoal after;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final bool changed = after.totalSaved != before.totalSaved;
    final Color color = after.isReached ? money.income : colors.primary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  changed ? 'After adding'.tr : 'Saved so far'.tr,
                  style: text.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${AppFormatters.number(after.progress * 100, decimalDigits: 0)}%',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppProgressBar(value: after.progress, color: color),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '@spent of @amount'.trParams(<String, String>{
              'spent': AppFormatters.money(after.totalSaved),
              'amount': AppFormatters.money(after.targetAmount),
            }),
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (after.isReached)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusPill(
                label: before.isReached
                    ? 'Goal reached'.tr
                    : 'This reaches your goal'.tr,
                color: money.income,
                icon: Icons.check_circle_outline,
              ),
            )
          else
            Text(
              '@amount left'.trParams(<String, String>{
                'amount': AppFormatters.money(after.remaining),
              }),
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
