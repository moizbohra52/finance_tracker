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
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/features/accounts/views/account_list_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Add an account, or edit the [Account] passed as the route argument. This
/// is where an account's opening balance and its date are set.
class AccountFormView extends StatefulWidget {
  const AccountFormView({super.key});

  @override
  State<AccountFormView> createState() => _AccountFormViewState();
}

class _AccountFormViewState extends State<AccountFormView> {
  final AccountController _controller = Get.find<AccountController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _opening = TextEditingController(text: '0');

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = AccountController.newId();
  late final Account? _existing;
  AccountType _type = AccountType.cash;
  DateTime _openingDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    _existing = args is Account ? args : null;
    final Account? a = _existing;
    if (a != null) {
      _name.text = a.name;
      _type = a.type;
      _opening.text = a.openingBalance.toString();
      _openingDate = a.openingBalanceDate ?? a.createdAt;
    }
    _controller.save.error.value = null;
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool saved = await _controller.saveAccount(
      id: _existing?.id ?? _id,
      existing: _existing,
      name: _name.text.trim(),
      type: _type,
      openingBalance: Decimal.parse(_opening.text.trim()),
      openingBalanceDate: _openingDate,
    );
    if (!saved) return;
    AppSnackbar.show(_existing == null ? 'Account added' : 'Account updated');
    Get.back<void>();
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = _existing != null;
    return Scaffold(
      appBar: AppAppBar(title: editing ? 'Edit account' : 'Add account'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 120,
          child: Form(
            key: _formKey,
            child: ListView(
              children: <Widget>[
                AppTextField(
                  label: 'Account name',
                  controller: _name,
                  autofocus: !editing,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      Validators.name(v, 'an account name'),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<AccountType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Account type'),
                  items: <DropdownMenuItem<AccountType>>[
                    for (final AccountType t in AccountType.values)
                      DropdownMenuItem<AccountType>(
                        value: t,
                        child: Text(accountTypeLabel(t)),
                      ),
                  ],
                  onChanged: (AccountType? v) =>
                      setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Opening balance',
                  controller: _opening,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  helperText: 'Money in this account when you start tracking.',
                  validator: Validators.nonNegativeAmount,
                ),
                const SizedBox(height: AppSpacing.md),
                AppDateField(
                  label: 'Opening balance date',
                  value: _openingDate,
                  lastDate: DateTime.now(),
                  onChanged: (DateTime d) => setState(() => _openingDate = d),
                ),
                const SizedBox(height: AppSpacing.lg),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: editing ? 'Save changes' : 'Add account',
                    icon: Icons.check_rounded,
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
