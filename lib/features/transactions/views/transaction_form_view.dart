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
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Add or edit an income/expense. Amount first, then category, then account.
class TransactionFormView extends StatefulWidget {
  const TransactionFormView({super.key});

  @override
  State<TransactionFormView> createState() => _TransactionFormViewState();
}

class _TransactionFormViewState extends State<TransactionFormView> {
  final TransactionController _controller = Get.find<TransactionController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = TransactionController.newId();
  late final Transaction? _existing;
  late TransactionType _type;
  String? _accountId;
  String? _categoryId;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    final TransactionFormArgs formArgs = args is TransactionFormArgs
        ? args
        : const TransactionFormArgs();
    _existing = formArgs.existing;
    _type = formArgs.type;
    _date = DateTime.now();
    final Transaction? existing = _existing;
    if (existing != null) {
      _amount.text = existing.amount.toString();
      _note.text = existing.note ?? '';
      _accountId = existing.accountId;
      _categoryId = existing.categoryId;
      _date = existing.transactionDate;
    }
    _controller.save.error.value = null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isEditing => _existing != null;

  /// Keeps the chosen account valid. A new transaction starts on the account
  /// set as default in Settings when it still exists, else the first account.
  String? _effectiveAccount(List<Account> accounts) {
    if (accounts.any((Account a) => a.id == _accountId)) return _accountId;
    final String? defaultId =
        Get.find<SettingsController>().preferences.value.defaultAccountId;
    if (accounts.any((Account a) => a.id == defaultId)) return defaultId;
    return accounts.isEmpty ? null : accounts.first.id;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final String? accountId = _effectiveAccount(_controller.accounts);
    if (accountId == null) return;
    final String note = _note.text.trim();
    final bool saved = await _controller.saveTransaction(
      id: _existing?.id ?? _id,
      existing: _existing,
      type: _type,
      amount: Decimal.parse(_amount.text.trim()),
      accountId: accountId,
      categoryId: _categoryId,
      date: _date,
      note: note.isEmpty ? null : note,
    );
    if (!saved) return;
    AppSnackbar.show(
      _isEditing
          ? 'Transaction updated'
          : '${_type == TransactionType.income ? 'Income' : 'Expense'} added',
    );
    Get.back<void>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: _isEditing
            ? 'Edit transaction'
            : (_type == TransactionType.income ? 'Add income' : 'Add expense'),
      ),
      body: SafeArea(
        child: Obx(() {
          if (!_controller.lookupsLoaded.value) {
            return const LoadingState(message: 'Loading accounts');
          }
          final String? lookupError = _controller.lookupError.value;
          if (lookupError != null && _controller.accounts.isEmpty) {
            return ErrorState(
              message: lookupError,
              onRetry: _controller.loadLookups,
            );
          }
          if (_controller.accounts.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Add an account first',
              message:
                  'Transactions are recorded against an account such as Cash '
                  'or a bank account.',
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
    final String? accountId = _effectiveAccount(accounts);

    return AppContent(
      maxWidth: AppSizes.maxContentWidth + 120,
      child: Form(
        key: _formKey,
        child: ListView(
          children: <Widget>[
            if (!_isEditing)
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
              autofocus: !_isEditing,
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
              initialValue: accountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Account'),
              items: <DropdownMenuItem<String>>[
                for (final Account a in accounts)
                  DropdownMenuItem<String>(value: a.id, child: Text(a.name)),
              ],
              onChanged: (String? v) => setState(() => _accountId = v),
              validator: (String? v) => v == null ? 'Choose an account' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppDateField(
              label: 'Date',
              value: _date,
              lastDate: DateTime.now().add(const Duration(days: 1)),
              onChanged: (DateTime picked) => setState(() {
                // Keep the time of day so same-day entries stay ordered.
                _date = DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  _date.hour,
                  _date.minute,
                );
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Note (optional)',
              controller: _note,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSpacing.lg),
            SubmitErrorMessage(_controller.save),
            Obx(
              () => AppButton(
                label: _isEditing ? 'Save changes' : 'Save',
                icon: Icons.check_rounded,
                isLoading: _controller.save.isBusy.value,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
