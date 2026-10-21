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
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/categories/controller/category_controller.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/widgets/receipt_field.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/category_picker.dart';
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
  late TimeOfDay _time;

  // Applied on Save, so leaving the form discards them.
  ({Uint8List bytes, String fileName})? _newReceipt;
  bool _removeReceipt = false;

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
    _time = TimeOfDay.now();
    final Transaction? existing = _existing;
    if (existing != null) {
      _amount.text = existing.amount.toString();
      _note.text = existing.note ?? '';
      _accountId = existing.accountId;
      _categoryId = existing.categoryId;
      _date = existing.transactionDate;
      _time = TimeOfDay.fromDateTime(existing.transactionDate);
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
    final DateTime combinedDate = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
      DateTime.now().second,
    );
    final bool saved = await _controller.saveTransaction(
      id: _existing?.id ?? _id,
      existing: _existing,
      type: _type,
      amount: Decimal.parse(_amount.text.trim()),
      accountId: accountId,
      categoryId: _categoryId,
      date: combinedDate,
      note: note.isEmpty ? null : note,
      newReceipt: _newReceipt,
      removeReceipt: _removeReceipt && _newReceipt == null,
    );
    if (!saved) return;
    AppSnackbar.show(
      _isEditing
          ? 'Transaction updated'.tr
          : (_type == TransactionType.income
                ? 'Income added'.tr
                : 'Expense added'.tr),
    );
    Get.back<void>();
  }

  /// Opens the category form for this kind and selects what it creates.
  Future<void> _createCategory() async {
    // GetX routes are typed dynamic, so the id comes back untyped.
    final Object? id = await Get.toNamed<dynamic>(
      AppRoutes.categoryForm,
      arguments: CategoryFormArgs(
        type: _type == TransactionType.income
            ? CategoryType.income
            : CategoryType.expense,
      ),
    );
    if (id is String && mounted) setState(() => _categoryId = id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: _isEditing
            ? 'Edit transaction'.tr
            : (_type == TransactionType.income
                  ? 'Add income'.tr
                  : 'Add expense'.tr),
      ),
      body: SafeArea(
        child: Obx(() {
          if (!_controller.lookupsLoaded.value) {
            return LoadingState(message: 'Loading accounts'.tr);
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
              title: 'Add an account first'.tr,
              message:
                  'Transactions are recorded against an account such as Cash or a bank account.'
                      .tr,
              actionLabel: 'Add account'.tr,
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
          clipBehavior: Clip.none,
          padding: const EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: AppSpacing.xxl,
          ),
          children: <Widget>[
            const SizedBox(height: AppSpacing.xs),
            if (!_isEditing)
              SegmentedButton<TransactionType>(
                segments: <ButtonSegment<TransactionType>>[
                  ButtonSegment<TransactionType>(
                    value: TransactionType.expense,
                    icon: const Icon(Icons.north_east_rounded),
                    label: Text('Expense'.tr),
                  ),
                  ButtonSegment<TransactionType>(
                    value: TransactionType.income,
                    icon: const Icon(Icons.south_west_rounded),
                    label: Text('Income'.tr),
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
              scrollPadding: const EdgeInsets.only(
                top: 80,
                bottom: 90,
                left: 16,
                right: 16,
              ),
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
              decoration: InputDecoration(
                labelText: 'Amount'.tr,
                prefixText: '${AppFormatters.currencySymbol} ',
                prefixStyle: text.displaySmall,
                hintText: '0.00',
                hintStyle: text.displaySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Category'.tr, style: text.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            CategoryPicker(
              categories: categories,
              type: _type,
              selectedId: _categoryId,
              onChanged: (String? id) => setState(() => _categoryId = id),
              onAddNew: _createCategory,
            ),
            const SizedBox(height: AppSpacing.lg),
            BottomSheetDropdown<String>(
              value: accountId,
              options: <String>[for (final Account a in accounts) a.id],
              labelOf: (String id) =>
                  accounts.firstWhere((Account a) => a.id == id).name,
              decoration: InputDecoration(labelText: 'Account'.tr),
              onChanged: (String? v) => setState(() => _accountId = v),
              validator: (String? v) =>
                  v == null ? 'Choose an account'.tr : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: AppDateField(
                    label: 'Date'.tr,
                    value: _date,
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    onChanged: (DateTime picked) =>
                        setState(() => _date = picked),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppTimeField(
                    label: 'Time'.tr,
                    value: _time,
                    onChanged: (TimeOfDay picked) =>
                        setState(() => _time = picked),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Note (optional)'.tr,
              controller: _note,
              minLines: 3,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: AppSpacing.md),
            ReceiptField(
              existingPath: _existing?.attachmentUrl,
              transactionId: _existing?.id ?? _id,
              onPicked: (({Uint8List bytes, String fileName})? receipt) =>
                  _newReceipt = receipt,
              onRemoved: () => _removeReceipt = true,
            ),
            const SizedBox(height: AppSpacing.lg),
            SubmitErrorMessage(_controller.save),
            Obx(
              () => AppButton(
                label: _isEditing ? 'Save changes'.tr : 'Save'.tr,
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
