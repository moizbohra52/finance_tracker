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
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/widgets/account_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

String contactEntryLabel(ContactTransactionType type) => switch (type) {
  ContactTransactionType.credit => 'Credit'.tr,
  ContactTransactionType.debit => 'Debit'.tr,
  ContactTransactionType.paymentReceived => 'Payment received'.tr,
  ContactTransactionType.paymentMade => 'Payment made'.tr,
  ContactTransactionType.adjustment => 'Adjustment'.tr,
};

/// Plain-language effect of each entry type on the balance.
String contactEntryHint(ContactTransactionType type) => switch (type) {
  ContactTransactionType.credit => 'They owe you more.'.tr,
  ContactTransactionType.debit => 'You owe them more.'.tr,
  ContactTransactionType.paymentReceived => 'They paid you back.'.tr,
  ContactTransactionType.paymentMade => 'You paid them back.'.tr,
  ContactTransactionType.adjustment => 'Corrects the balance.'.tr,
};

/// Add credit, debit or a settlement for the contact in the route arguments.
class ContactEntryView extends StatefulWidget {
  const ContactEntryView({super.key});

  @override
  State<ContactEntryView> createState() => _ContactEntryViewState();
}

class _ContactEntryViewState extends State<ContactEntryView> {
  static const List<ContactTransactionType> _choices = <ContactTransactionType>[
    ContactTransactionType.credit,
    ContactTransactionType.debit,
    ContactTransactionType.paymentReceived,
    ContactTransactionType.paymentMade,
  ];

  final ContactFormController _controller = Get.find<ContactFormController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  // One id per form, so a retried save is an idempotent upsert.
  final String _id = ContactFormController.newId();

  ContactEntryArgs? _args;
  ContactTransactionType _type = ContactTransactionType.credit;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  DateTime? _dueDate;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    if (args is ContactEntryArgs) {
      _args = args;
      _type = args.type;
      final ContactTransaction? e = args.existing;
      if (e != null) {
        _amount.text = e.amount.toString();
        _date = e.transactionDate;
        _time = TimeOfDay.fromDateTime(e.transactionDate);
        _dueDate = e.dueDate;
        _note.text = e.note ?? '';
        _controller.getLinkedTransaction(e.id).then((Transaction? tx) {
          if (mounted && tx != null) {
            setState(() => _accountId = tx.accountId);
          }
        });
      }
    }
    _controller.save.error.value = null;
    _controller.loadAccounts();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ContactEntryArgs? args = _args;
    if (args == null || !(_formKey.currentState?.validate() ?? false)) return;
    final bool editing = args.existing != null;
    final String note = _note.text.trim();
    final DateTime combinedDate = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
      DateTime.now().second,
    );
    final bool saved = await _controller.saveEntry(
      id: args.existing?.id ?? _id,
      existing: args.existing,
      contactId: args.contactId,
      contactName: args.contactName,
      type: _type,
      amount: Decimal.parse(_amount.text.trim()),
      date: combinedDate,
      dueDate: _dueDate,
      note: note.isEmpty ? null : note,
      accountId: _accountId,
    );
    if (!saved) return;
    AppSnackbar.show(
      editing
          ? 'Entry updated'.tr
          : (_accountId != null
              ? '@entry recorded & account updated'.trParams(<String, String>{
                  'entry': contactEntryLabel(_type),
                })
              : '@entry recorded'.trParams(<String, String>{
                  'entry': contactEntryLabel(_type),
                })),
    );
    Get.back<void>();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool editing = _args?.existing != null;
    return Scaffold(
      appBar: AppAppBar(
        title: editing
            ? 'Edit entry'.tr
            : (_args?.contactName == null
                ? 'Add entry'.tr
                : 'Entry for @name'.trParams(<String, String>{'name': _args!.contactName!})),
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
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final ContactTransactionType t in _choices)
                      ChoiceChip(
                        label: Text(contactEntryLabel(t)),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(contactEntryHint(_type), style: text.bodySmall),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _amount,
                  autofocus: !editing,
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: AppDateField(
                        label: 'Date'.tr,
                        value: _date,
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                        onChanged: (DateTime d) => setState(() => _date = d),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppTimeField(
                        label: 'Time'.tr,
                        value: _time,
                        onChanged: (TimeOfDay t) => setState(() => _time = t),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppDateField(
                  label: 'Due date (optional)'.tr,
                  value: _dueDate,
                  onChanged: (DateTime d) => setState(() => _dueDate = d),
                  onCleared: () => setState(() => _dueDate = null),
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
                Obx(() {
                  final List<Account> accounts = _controller.accounts;
                  if (accounts.isEmpty) return const SizedBox.shrink();

                  final bool isOutflow =
                      _type == ContactTransactionType.credit ||
                      _type == ContactTransactionType.paymentMade;
                  final String label = isOutflow
                      ? 'Paid from account (optional)'.tr
                      : 'Deposit into account (optional)'.tr;
                  final String helper = isOutflow
                      ? 'Deducts amount from this account'.tr
                      : 'Adds amount to this account'.tr;

                  return BottomSheetDropdown<String?>(
                    value: _accountId,
                    options: <String?>[
                      null,
                      for (final Account a in accounts) a.id,
                    ],
                    labelOf: (String? id) {
                      if (id == null) return 'None (Khata only)'.tr;
                      final Account? a = accounts.firstWhereOrNull(
                        (Account a) => a.id == id,
                      );
                      return a?.name ?? 'Unknown account'.tr;
                    },
                    detailOf: (String? id) {
                      if (id == null) {
                        return 'Only updates this contact\'s balance'.tr;
                      }
                      final Account? a = accounts.firstWhereOrNull(
                        (Account a) => a.id == id,
                      );
                      return a != null
                          ? '${accountTypeLabel(a.type)} · $helper'
                          : '';
                    },
                    decoration: InputDecoration(
                      labelText: label,
                      helperText: _accountId != null
                          ? helper
                          : 'Optional: record in bank or cash balance as well'.tr,
                      helperMaxLines: 2,
                      prefixIcon: Icon(
                        isOutflow
                            ? Icons.call_made_rounded
                            : Icons.call_received_rounded,
                      ),
                      suffixIcon: _accountId != null
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                size: 20,
                              ),
                              tooltip: 'Clear account'.tr,
                              onPressed: () =>
                                  setState(() => _accountId = null),
                            )
                          : null,
                    ),
                    onChanged: (String? val) =>
                        setState(() => _accountId = val),
                  );
                }),
                const SizedBox(height: AppSpacing.lg),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: editing
                        ? 'Save changes'.tr
                        : 'Save @entry'.trParams(<String, String>{
                            'entry': contactEntryLabel(_type).toLowerCase(),
                          }),
                    icon: Icons.check_rounded,
                    isLoading: _controller.save.isBusy.value,
                    onPressed: _args == null ? null : _submit,
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
