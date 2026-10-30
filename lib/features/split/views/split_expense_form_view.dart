import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_bottom_sheet_dropdown.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/features/split/controllers/split_expense_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The split expense form: amount, paid by, split mode per member, category,
/// account and note, with a live preview. All numbers come from the
/// controller's getters; the view does no maths.
class SplitExpenseFormView extends StatefulWidget {
  const SplitExpenseFormView({super.key});

  @override
  State<SplitExpenseFormView> createState() => _SplitExpenseFormViewState();
}

class _SplitExpenseFormViewState extends State<SplitExpenseFormView> {
  final SplitExpenseController _controller = Get.find();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _total = TextEditingController();
  DateTime _date = DateTime.now();
  SplitExpenseArgs? _args;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final Object? arguments = Get.arguments;
    if (arguments is SplitExpenseArgs) {
      _args = arguments;
      _controller
          .start(groupId: arguments.groupId, existing: arguments.existing)
          .then((_) {
            if (!mounted) return;
            setState(() {
              _started = true;
              _date = arguments.existing?.expense.expenseDate ?? DateTime.now();
              _title.text = arguments.existing?.expense.title ?? '';
              _note.text = arguments.existing?.expense.note ?? '';
              _total.text = _controller.totalText.value;
            });
          });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _total.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool ok = await _controller.saveExpense(
      id: _args?.existing?.expense.id ?? SplitExpenseController.newId(),
      title: _title.text,
      date: _date,
      note: _note.text,
    );
    if (!ok || !mounted) return;
    Get.back<void>();
    AppSnackbar.show(
      _args?.existing == null ? 'Expense split saved'.tr : 'Split updated'.tr,
    );
  }

  Future<void> _delete() async {
    final SplitExpenseDetail? existing = _args?.existing;
    if (existing == null) return;
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this expense?'.tr,
      message:
          'Your expense, khata entries and account movement go with it.'.tr,
      confirmLabel: 'Delete'.tr,
    );
    if (!confirmed || !mounted) return;
    final bool ok = await _controller.deleteExpense(existing.expense.id);
    if (!ok || !mounted) return;
    Get.back<void>();
    AppSnackbar.show('Split deleted'.tr);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppAppBar(
        title: _args?.existing == null ? 'Split expense'.tr : 'Edit split'.tr,
        actions: <Widget>[
          if (_args?.existing != null)
            IconButton(
              tooltip: 'Delete expense'.tr,
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: AppContent(
        child: !_started
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  children: <Widget>[
                    AppTextField(
                      label: 'Title'.tr,
                      controller: _title,
                      validator: (String? v) => (v == null || v.trim().isEmpty)
                          ? 'Give the expense a title'.tr
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Total amount'.tr,
                      controller: _total,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: Validators.positiveAmount,
                      onChanged: (String v) => _controller.totalText.value = v,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppDateField(
                      label: 'Date'.tr,
                      value: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      onChanged: (DateTime d) => setState(() => _date = d),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Paid by'.tr, style: text.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Obx(
                      () => SegmentedButton<bool>(
                        segments: <ButtonSegment<bool>>[
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Me'.tr),
                            icon: const Icon(Icons.person_outline),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Multiple'.tr),
                            icon: const Icon(Icons.groups_outlined),
                          ),
                        ],
                        selected: <bool>{_controller.multiplePayers.value},
                        onSelectionChanged: (Set<bool> selection) =>
                            _controller.multiplePayers.value = selection.first,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Obx(() {
                      if (!_controller.multiplePayers.value) {
                        return BottomSheetDropdown<String>(
                          value: _controller.payerId.value,
                          options: <String>[
                            for (final SplitMember m in _controller.members)
                              m.id,
                          ],
                          labelOf: (String id) =>
                              _controller.memberNameById(id),
                          decoration: InputDecoration(labelText: 'Who paid'.tr),
                          onChanged: (String? v) =>
                              _controller.payerId.value = v ?? '',
                        );
                      }
                      return _AmountsPerMember(controller: _controller);
                    }),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Split'.tr, style: text.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Obx(
                      () => SegmentedButton<SplitMode>(
                        segments: <ButtonSegment<SplitMode>>[
                          ButtonSegment<SplitMode>(
                            value: SplitMode.equal,
                            label: Text('Equal'.tr),
                          ),
                          ButtonSegment<SplitMode>(
                            value: SplitMode.exact,
                            label: Text('Exact'.tr),
                          ),
                          ButtonSegment<SplitMode>(
                            value: SplitMode.percent,
                            label: Text('%'.tr),
                          ),
                          ButtonSegment<SplitMode>(
                            value: SplitMode.shares,
                            label: Text('Shares'.tr),
                          ),
                        ],
                        selected: <SplitMode>{_controller.mode.value},
                        onSelectionChanged: (Set<SplitMode> selection) =>
                            _controller.mode.value = selection.first,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _SplitRows(controller: _controller),
                    const SizedBox(height: AppSpacing.md),
                    Obx(() {
                      if (_controller.mode.value == SplitMode.equal) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        '@amount left'.trParams(<String, String>{
                          'amount': '${_controller.sharesLeft}',
                        }),
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      );
                    }),
                    const SizedBox(height: AppSpacing.md),
                    Obx(
                      () => BottomSheetDropdown<String>(
                        value: _controller.categoryId.value,
                        options: <String>[
                          for (final Category c in _controller.categories) c.id,
                        ],
                        labelOf: (String id) => _controller.categories
                            .firstWhere((Category c) => c.id == id)
                            .name,
                        decoration: InputDecoration(labelText: 'Category'.tr),
                        onChanged: (String? v) =>
                            _controller.categoryId.value = v,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Obx(
                      () => BottomSheetDropdown<String>(
                        value: _controller.accountId.value,
                        options: <String>[
                          for (final Account a in _controller.accounts) a.id,
                        ],
                        labelOf: (String id) => _controller.accounts
                            .firstWhere((Account a) => a.id == id)
                            .name,
                        decoration: InputDecoration(labelText: 'Account'.tr),
                        onChanged: (String? v) =>
                            _controller.accountId.value = v,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(label: 'Note'.tr, controller: _note),
                    const SizedBox(height: AppSpacing.md),
                    Obx(() {
                      final ({Decimal yourShare, Decimal youGet})? preview =
                          _controller.preview;
                      if (preview == null) return const SizedBox.shrink();
                      final String right = preview.youGet >= Decimal.zero
                          ? 'You get @amount'.trParams(<String, String>{
                              'amount': AppFormatters.money(preview.youGet),
                            })
                          : 'You owe @amount'.trParams(<String, String>{
                              'amount': AppFormatters.money(-preview.youGet),
                            });
                      return Text(
                        'Your share @share · @right'.trParams(<String, String>{
                          'share': AppFormatters.money(preview.yourShare),
                          'right': right,
                        }),
                        style: text.titleSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }),
                    const SizedBox(height: AppSpacing.md),
                    Obx(() => InlineError(message: _controller.error)),
                    SubmitErrorMessage(_controller.save),
                    Obx(
                      () => AppButton(
                        label: 'Save'.tr,
                        icon: Icons.check_rounded,
                        onPressed: _save,
                        isLoading: _controller.save.isBusy.value,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The per-member paid amounts, shown for multiple payers.
class _AmountsPerMember extends StatelessWidget {
  const _AmountsPerMember({required this.controller});

  final SplitExpenseController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Column(
        children: <Widget>[
          for (final SplitMember m in controller.members)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _MemberField(
                memberId: m.id,
                label: controller.memberName(m),
                text: controller.paidText,
              ),
            ),
          Text(
            '@amount left'.trParams(<String, String>{
              'amount': AppFormatters.money(controller.paidLeft),
            }),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One amount field bound to one member's entry in [text].
class _MemberField extends StatefulWidget {
  const _MemberField({
    required this.memberId,
    required this.label,
    required this.text,
  });

  final String memberId;
  final String label;
  final RxMap<String, String> text;

  @override
  State<_MemberField> createState() => _MemberFieldState();
}

class _MemberFieldState extends State<_MemberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text[widget.memberId] ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      controller: _controller,
      onChanged: (String v) => widget.text[widget.memberId] = v,
    );
  }
}

/// One row per member: a tick in equal mode, an amount input otherwise.
class _SplitRows extends StatelessWidget {
  const _SplitRows({required this.controller});

  final SplitExpenseController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final SplitMode mode = controller.mode.value;
      return Column(
        children: <Widget>[
          for (final SplitMember m in controller.members)
            switch (mode) {
              SplitMode.equal => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: controller.ticked.contains(m.id),
                title: Text(controller.memberName(m)),
                onChanged: (bool? checked) {
                  if (checked ?? false) {
                    controller.ticked.add(m.id);
                  } else {
                    controller.ticked.remove(m.id);
                  }
                },
              ),
              _ => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _MemberField(
                  memberId: m.id,
                  label: controller.memberName(m),
                  text: controller.inputText,
                ),
              ),
            },
        ],
      );
    });
  }
}

/// Shows the controller's first validation message, if any.
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final String? text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}
