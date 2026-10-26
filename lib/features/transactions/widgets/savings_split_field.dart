import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_bottom_sheet_dropdown.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/savings_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Rows of goal + amount that put parts of an income into savings goals.
/// Each row's text is kept here; [onChanged] reports the rows that are
/// complete. Validation rides on the parent [Form].
class SavingsSplitField extends StatefulWidget {
  const SavingsSplitField({
    super.key,
    required this.amount,
    required this.goals,
    required this.initial,
    required this.onChanged,
    required this.onCreateGoal,
  });

  /// The income amount the rows are measured against.
  final TextEditingController amount;
  final List<SavingsGoal> goals;

  /// Rows to start with. Read once, so build the field after they are known.
  final List<SavingsPart> initial;
  final ValueChanged<List<SavingsPart>> onChanged;

  /// Opens the goal form, for a user who has no goal yet.
  final VoidCallback onCreateGoal;

  @override
  State<SavingsSplitField> createState() => _SavingsSplitFieldState();
}

class _SplitRow {
  _SplitRow({this.goalId, String amount = ''})
    : amount = TextEditingController(text: amount);

  String? goalId;
  final TextEditingController amount;
}

class _SavingsSplitFieldState extends State<SavingsSplitField> {
  final List<_SplitRow> _rows = <_SplitRow>[];
  final GlobalKey<FormFieldState<void>> _split =
      GlobalKey<FormFieldState<void>>();

  @override
  void initState() {
    super.initState();
    for (final SavingsPart p in widget.initial) {
      _rows.add(_SplitRow(goalId: p.goalId, amount: p.amount.toString()));
    }
    widget.amount.addListener(_revalidate);
  }

  @override
  void dispose() {
    widget.amount.removeListener(_revalidate);
    for (final _SplitRow row in _rows) {
      row.amount.dispose();
    }
    super.dispose();
  }

  SavingsPart? _partOf(_SplitRow row) {
    final String? goalId = row.goalId;
    final Decimal? amount = Decimal.tryParse(row.amount.text.trim());
    if (goalId == null || amount == null) return null;
    return (goalId: goalId, amount: amount);
  }

  /// The rows with a goal and an amount that parses.
  List<SavingsPart> _parts() => <SavingsPart>[
    for (final _SplitRow row in _rows)
      if (_partOf(row) case final SavingsPart part) part,
  ];

  /// The error for the rows together, or null. Left to the amount field while
  /// the income has no valid amount yet.
  String? _splitError() {
    final Decimal? income = Decimal.tryParse(widget.amount.text.trim());
    if (income == null) return null;
    return SavingsSplit.validate(
      type: TransactionType.income,
      amount: income,
      parts: _parts(),
    )?.tr;
  }

  /// Once the rows have failed a Save, the error follows every edit.
  void _revalidate() {
    final FormFieldState<void>? state = _split.currentState;
    if (state != null && state.hasError) state.validate();
  }

  void _changed() {
    setState(() {});
    _revalidate();
    widget.onChanged(_parts());
  }

  void _remove(_SplitRow row) {
    _rows.remove(row);
    _changed();
    row.amount.dispose();
  }

  String _nameOf(String goalId) {
    for (final SavingsGoal goal in widget.goals) {
      if (goal.id == goalId) return goal.name;
    }
    return 'Savings goal'.tr;
  }

  Set<String> get _usedGoalIds => <String>{
    for (final _SplitRow row in _rows)
      if (row.goalId case final String id) id,
  };

  Widget _rowTile(_SplitRow row) {
    final Set<String> usedElsewhere = <String>{
      for (final _SplitRow other in _rows)
        if (other != row)
          if (other.goalId case final String id) id,
    };
    final String? own = row.goalId;
    final List<String> options = <String>[
      for (final SavingsGoal goal in widget.goals)
        if (!usedElsewhere.contains(goal.id)) goal.id,
      // A goal that is no longer loaded still names the row it was saved on.
      if (own != null && !widget.goals.any((SavingsGoal g) => g.id == own)) own,
    ];
    return Padding(
      key: ObjectKey(row),
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: BottomSheetDropdown<String>(
              value: row.goalId,
              options: options,
              labelOf: _nameOf,
              decoration: InputDecoration(labelText: 'Savings goal'.tr),
              onChanged: (String? id) {
                row.goalId = id;
                _changed();
              },
              validator: (String? v) => v == null ? 'Choose a goal'.tr : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: AppTextField(
              label: 'Amount'.tr,
              controller: row.amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              validator: Validators.positiveAmount,
              onChanged: (_) => _changed(),
            ),
          ),
          IconButton(
            tooltip: 'Remove'.tr,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _remove(row),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListenableBuilder(
          listenable: widget.amount,
          builder: (BuildContext context, Widget? _) {
            final Decimal income =
                Decimal.tryParse(widget.amount.text.trim()) ?? Decimal.zero;
            final Decimal saved = SavingsSplit.total(_parts());
            return Text(
              '@saved to savings · @left left'.trParams(<String, String>{
                'saved': AppFormatters.money(saved),
                'left': AppFormatters.money(income - saved),
              }),
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            );
          },
        ),
        FormField<void>(
          key: _split,
          validator: (_) => _splitError(),
          builder: (FormFieldState<void> state) => state.hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    state.errorText!,
                    style: text.bodySmall?.copyWith(color: colors.error),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasUnusedGoal = widget.goals.any(
      (SavingsGoal g) => !_usedGoalIds.contains(g.id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final _SplitRow row in _rows) _rowTile(row),
        if (_rows.isEmpty && widget.goals.isEmpty)
          TextButton(
            onPressed: widget.onCreateGoal,
            child: Text('Create a savings goal first'.tr),
          )
        else if (_rows.isEmpty)
          TextButton.icon(
            onPressed: () => setState(() => _rows.add(_SplitRow())),
            icon: const Icon(Icons.savings_outlined),
            label: Text('Put some in savings'.tr),
          )
        else ...<Widget>[
          if (hasUnusedGoal)
            TextButton.icon(
              onPressed: () => setState(() => _rows.add(_SplitRow())),
              icon: const Icon(Icons.add_rounded),
              label: Text('Another goal'.tr),
            ),
          _footer(context),
        ],
      ],
    );
  }
}
