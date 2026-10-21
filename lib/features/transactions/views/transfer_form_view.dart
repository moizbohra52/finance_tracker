import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
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
import 'package:finance_tracker/domain/services/transfer_legs.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Moves money between two of the user's accounts. Amount first, then the
/// accounts. A transfer is not income or expense: it changes the two
/// account balances and leaves the total unchanged.
class TransferFormView extends StatefulWidget {
  const TransferFormView({super.key});

  @override
  State<TransferFormView> createState() => _TransferFormViewState();
}

class _TransferFormViewState extends State<TransferFormView> {
  final TransactionController _controller = Get.find<TransactionController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  // One set of ids per form, so a retried save is an idempotent upsert.
  final TransferIds _ids = TransferIds();
  late final TransferFormArgs _args;

  /// The transfer being edited, once loaded.
  TransferLegs? _existing;
  bool _loadingExisting = false;
  String? _loadError;

  String? _fromId;
  String? _toId;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();

  bool get _isEditing => _args.transferId != null;

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    _args = args is TransferFormArgs ? args : const TransferFormArgs();
    _fromId = _args.fromAccountId;
    _controller.save.error.value = null;
    if (_isEditing) _loadExisting();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() {
      _loadingExisting = true;
      _loadError = null;
    });
    try {
      final TransferLegs? legs = await _controller.fetchTransfer(
        _args.transferId!,
      );
      if (!mounted) return;
      setState(() {
        _existing = legs;
        if (legs != null) {
          _amount.text = legs.amount.toString();
          _note.text = legs.note ?? '';
          _fromId = legs.fromAccountId;
          _toId = legs.toAccountId;
          _date = legs.date;
          _time = TimeOfDay.fromDateTime(legs.date);
        }
      });
    } on AppException catch (failure) {
      if (mounted) setState(() => _loadError = failure.message);
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  /// The source: the chosen one while it exists, else the first account.
  String? _effectiveFrom(List<Account> accounts) {
    if (accounts.any((Account a) => a.id == _fromId)) return _fromId;
    return accounts.isEmpty ? null : accounts.first.id;
  }

  /// The destination: the chosen one while it exists and differs from the
  /// source, else the first other account.
  String? _effectiveTo(List<Account> accounts, String? fromId) {
    if (_toId != fromId && accounts.any((Account a) => a.id == _toId)) {
      return _toId;
    }
    for (final Account a in accounts) {
      if (a.id != fromId) return a.id;
    }
    return null;
  }

  void _swap(String? fromId, String? toId) => setState(() {
    _fromId = toId;
    _toId = fromId;
  });

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final List<Account> accounts = _controller.accounts.toList();
    final String? fromId = _effectiveFrom(accounts);
    final String? toId = _effectiveTo(accounts, fromId);
    if (fromId == null || toId == null) return;
    final String note = _note.text.trim();
    final DateTime combinedDate = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
      DateTime.now().second,
    );
    final TransferLegs? existing = _existing;
    final TransferLegs? saved = await _controller.saveTransfer(
      newIds: _ids,
      existing: existing,
      fromAccountId: fromId,
      toAccountId: toId,
      amount: Decimal.parse(_amount.text.trim()),
      date: combinedDate,
      note: note.isEmpty ? null : note,
    );
    if (saved == null) return;
    AppSnackbar.show(_isEditing ? 'Transfer updated'.tr : 'Transfer saved'.tr);
    if (existing != null && saved.transferId != existing.transferId) {
      // The edit replaced the rows, so the detail screen below shows a
      // deleted leg: close it too.
      Get.until(
        (Route<dynamic> route) =>
            route.settings.name != AppRoutes.transferForm &&
            route.settings.name != AppRoutes.transactionDetail,
      );
    } else {
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: _isEditing ? 'Edit transfer'.tr : 'Transfer'.tr),
      body: SafeArea(
        child: Obx(() {
          if (!_controller.lookupsLoaded.value || _loadingExisting) {
            return LoadingState(message: 'Loading accounts'.tr);
          }
          final String? lookupError = _controller.lookupError.value;
          if (lookupError != null && _controller.accounts.isEmpty) {
            return ErrorState(
              message: lookupError,
              onRetry: _controller.loadLookups,
            );
          }
          final String? loadError = _loadError;
          if (loadError != null) {
            return ErrorState(message: loadError, onRetry: _loadExisting);
          }
          if (_isEditing && _existing == null) {
            return EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Transfer not found'.tr,
              message: 'It may have been deleted.'.tr,
            );
          }
          if (_controller.accounts.length < 2) {
            return EmptyState(
              icon: Icons.swap_horiz_rounded,
              title: 'Add another account'.tr,
              message:
                  'A transfer moves money between two of your accounts, for example from a bank account to cash.'.tr,
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
    final String? fromId = _effectiveFrom(accounts);
    final String? toId = _effectiveTo(accounts, fromId);
    String nameOf(String id) =>
        accounts.firstWhere((Account a) => a.id == id).name;
    final List<String> ids = <String>[for (final Account a in accounts) a.id];

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
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.35),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            BottomSheetDropdown<String>(
              value: fromId,
              options: ids,
              labelOf: nameOf,
              decoration: InputDecoration(
                labelText: 'From'.tr,
                prefixIcon: const Icon(Icons.north_east_rounded),
              ),
              onChanged: (String? v) => setState(() => _fromId = v),
            ),
            Center(
              child: IconButton(
                tooltip: 'Swap accounts'.tr,
                icon: const Icon(Icons.swap_vert_rounded),
                onPressed: () => _swap(fromId, toId),
              ),
            ),
            BottomSheetDropdown<String>(
              value: toId,
              // The source cannot also receive the money.
              options: <String>[
                for (final String id in ids)
                  if (id != fromId) id,
              ],
              labelOf: nameOf,
              decoration: InputDecoration(
                labelText: 'To'.tr,
                prefixIcon: const Icon(Icons.south_west_rounded),
              ),
              onChanged: (String? v) => setState(() => _toId = v),
              validator: (String? v) => v == null || v == fromId
                  ? 'Choose a different account to receive the money'.tr
                  : null,
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
            const SizedBox(height: AppSpacing.sm),
            Text(
              'A transfer is not counted as income or expense.'.tr,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SubmitErrorMessage(_controller.save),
            Obx(
              () => AppButton(
                label: _isEditing ? 'Save changes'.tr : 'Transfer'.tr,
                icon: Icons.swap_horiz_rounded,
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
