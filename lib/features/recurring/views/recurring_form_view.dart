import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/recurring/controllers/recurring_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// How the repeat is chosen in the form. "Custom" is "every N units" and is
/// stored as the unit plus an interval count.
enum _Repeat { daily, weekly, monthly, yearly, custom }

/// Add a recurring income/expense, or edit the rule passed as the argument.
class RecurringFormView extends StatefulWidget {
  const RecurringFormView({super.key});

  @override
  State<RecurringFormView> createState() => _RecurringFormViewState();
}

class _RecurringFormViewState extends State<RecurringFormView> {
  final RecurringController _controller = Get.find<RecurringController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _interval = TextEditingController(text: '2');

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = RecurringController.newId();
  late final RecurringTransaction? _existing;
  TransactionType _type = TransactionType.expense;
  String? _accountId;
  String? _categoryId;
  _Repeat _repeat = _Repeat.monthly;
  RecurringFrequency _unit = RecurringFrequency.monthly;
  late DateTime _start;
  DateTime? _end;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    _existing = args is RecurringTransaction ? args : null;
    final DateTime now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    final RecurringTransaction? r = _existing;
    if (r != null) {
      _type = r.type;
      _amount.text = r.amount.toString();
      _note.text = r.note ?? '';
      _accountId = r.accountId;
      _categoryId = r.categoryId;
      _start = r.startDate;
      _end = r.endDate;
      _unit = r.frequency;
      if (r.intervalCount != 1) {
        _repeat = _Repeat.custom;
        _interval.text = '${r.intervalCount}';
      } else {
        _repeat = _Repeat.values.byName(r.frequency.name);
      }
    }
    _controller.save.error.value = null;
    _controller.deletion.error.value = null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _interval.dispose();
    super.dispose();
  }

  bool get _editing => _existing != null;

  RecurringFrequency get _frequency => _repeat == _Repeat.custom
      ? _unit
      : RecurringFrequency.values.byName(_repeat.name);

  int get _intervalCount =>
      _repeat == _Repeat.custom ? int.parse(_interval.text.trim()) : 1;

  String? _effectiveAccount(List<Account> accounts) {
    if (accounts.any((Account a) => a.id == _accountId)) return _accountId;
    return accounts.isEmpty ? null : accounts.first.id;
  }

  Future<void> _submit() async {
    final bool valid = _formKey.currentState?.validate() ?? false;
    final String? dateError = _end != null && _end!.isBefore(_start)
        ? 'The end date must not be before the start date'
        : null;
    setState(() => _dateError = dateError);
    final String? accountId = _effectiveAccount(_controller.accounts);
    if (!valid || dateError != null || accountId == null) return;
    final String note = _note.text.trim();
    final bool saved = await _controller.saveRule(
      id: _existing?.id ?? _id,
      existing: _existing,
      accountId: accountId,
      categoryId: _categoryId,
      type: _type,
      amount: Decimal.parse(_amount.text.trim()),
      frequency: _frequency,
      intervalCount: _intervalCount,
      startDate: _start,
      endDate: _end,
      note: note.isEmpty ? null : note,
    );
    if (!saved) return;
    AppSnackbar.show(_editing ? 'Recurring updated' : 'Recurring added');
    Get.back<void>();
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this schedule?',
      message:
          'No new transactions will be created. Transactions already '
          'recorded stay.',
    );
    if (!confirmed) return;
    if (await _controller.deleteRule(_existing!.id)) {
      AppSnackbar.show('Recurring deleted');
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: _editing ? 'Edit recurring' : 'Add recurring'),
      body: SafeArea(
        child: Obx(() {
          if (!_controller.lookupsLoaded.value) {
            return const LoadingState(message: 'Loading accounts');
          }
          if (_controller.accounts.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Add an account first',
              message:
                  'A recurring transaction is recorded against an account.',
              actionLabel: 'Add account',
              onAction: () => Get.toNamed<void>(AppRoutes.accountForm),
            );
          }
          return _buildForm(context);
        }),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Account> accounts = _controller.accounts.toList();
    final List<Category> categories = _controller.categoriesFor(_type);
    final DateTime today = DateTime.now();
    final DateTime todayDay = DateTime(today.year, today.month, today.day);

    return AppContent(
      maxWidth: AppSizes.maxContentWidth + 120,
      child: Form(
        key: _formKey,
        child: ListView(
          children: <Widget>[
            SegmentedButton<TransactionType>(
              segments: const <ButtonSegment<TransactionType>>[
                ButtonSegment<TransactionType>(
                  value: TransactionType.expense,
                  icon: Icon(Icons.north_east_rounded),
                  label: Text('Expense'),
                ),
                ButtonSegment<TransactionType>(
                  value: TransactionType.income,
                  icon: Icon(Icons.south_west_rounded),
                  label: Text('Income'),
                ),
              ],
              selected: <TransactionType>{_type},
              onSelectionChanged: (Set<TransactionType> s) => setState(() {
                _type = s.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _amount,
              autofocus: !_editing,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.center,
              style: text.displaySmall,
              autovalidateMode: AutovalidateMode.onUserInteractionIfError,
              validator: Validators.positiveAmount,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                hintText: '0.00',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Category', style: text.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final Category c in categories)
                  ChoiceChip(
                    avatar: Icon(CategoryIcons.of(c.icon, _type), size: 18),
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (bool on) =>
                        setState(() => _categoryId = on ? c.id : null),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _effectiveAccount(accounts),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Account'),
              items: <DropdownMenuItem<String>>[
                for (final Account a in accounts)
                  DropdownMenuItem<String>(value: a.id, child: Text(a.name)),
              ],
              onChanged: (String? v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<_Repeat>(
              initialValue: _repeat,
              decoration: const InputDecoration(labelText: 'Repeats'),
              items: const <DropdownMenuItem<_Repeat>>[
                DropdownMenuItem<_Repeat>(
                  value: _Repeat.daily,
                  child: Text('Daily'),
                ),
                DropdownMenuItem<_Repeat>(
                  value: _Repeat.weekly,
                  child: Text('Weekly'),
                ),
                DropdownMenuItem<_Repeat>(
                  value: _Repeat.monthly,
                  child: Text('Monthly'),
                ),
                DropdownMenuItem<_Repeat>(
                  value: _Repeat.yearly,
                  child: Text('Yearly'),
                ),
                DropdownMenuItem<_Repeat>(
                  value: _Repeat.custom,
                  child: Text('Custom…'),
                ),
              ],
              onChanged: (_Repeat? v) => setState(() => _repeat = v ?? _repeat),
            ),
            if (_repeat == _Repeat.custom) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 120,
                    child: AppTextField(
                      label: 'Every',
                      controller: _interval,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: (String? v) {
                        final int? n = int.tryParse((v ?? '').trim());
                        return n == null || n < 1 || n > 365
                            ? '1 to 365'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: DropdownButtonFormField<RecurringFrequency>(
                      initialValue: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: <DropdownMenuItem<RecurringFrequency>>[
                        for (final RecurringFrequency f
                            in RecurringFrequency.values)
                          DropdownMenuItem<RecurringFrequency>(
                            value: f,
                            child: Text('${f.unit}s'),
                          ),
                      ],
                      onChanged: (RecurringFrequency? v) =>
                          setState(() => _unit = v ?? _unit),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppDateField(
              label: 'Starts',
              value: _start,
              // New schedules start today or later; nothing is back-filled.
              firstDate: _start.isBefore(todayDay) ? _start : todayDay,
              onChanged: (DateTime d) => setState(() => _start = d),
            ),
            const SizedBox(height: AppSpacing.md),
            AppDateField(
              label: 'Ends (optional)',
              value: _end,
              onChanged: (DateTime d) => setState(() => _end = d),
              onCleared: () => setState(() => _end = null),
            ),
            if (_dateError != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _dateError!,
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Note (optional)',
              controller: _note,
              helperText: 'For example: Rent, Netflix, Salary',
            ),
            const SizedBox(height: AppSpacing.lg),
            SubmitErrorMessage(_controller.save),
            Obx(
              () => AppButton(
                label: _editing ? 'Save changes' : 'Save',
                icon: Icons.check_rounded,
                isLoading: _controller.save.isBusy.value,
                onPressed: _submit,
              ),
            ),
            if (_editing) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              SubmitErrorMessage(_controller.deletion),
              Obx(
                () => AppButton(
                  label: 'Delete schedule',
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
    );
  }
}
