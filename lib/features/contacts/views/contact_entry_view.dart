import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

String contactEntryLabel(ContactTransactionType type) => switch (type) {
  ContactTransactionType.credit => 'Credit',
  ContactTransactionType.debit => 'Debit',
  ContactTransactionType.paymentReceived => 'Payment received',
  ContactTransactionType.paymentMade => 'Payment made',
  ContactTransactionType.adjustment => 'Adjustment',
};

/// Plain-language effect of each entry type on the balance.
String contactEntryHint(ContactTransactionType type) => switch (type) {
  ContactTransactionType.credit => 'They owe you more.',
  ContactTransactionType.debit => 'You owe them more.',
  ContactTransactionType.paymentReceived => 'They paid you back.',
  ContactTransactionType.paymentMade => 'You paid them back.',
  ContactTransactionType.adjustment => 'Corrects the balance.',
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
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    if (args is ContactEntryArgs) {
      _args = args;
      _type = args.type;
    }
    _controller.save.error.value = null;
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
    final String note = _note.text.trim();
    final bool saved = await _controller.saveEntry(
      id: _id,
      contactId: args.contactId,
      type: _type,
      amount: Decimal.parse(_amount.text.trim()),
      date: _date,
      dueDate: _dueDate,
      note: note.isEmpty ? null : note,
    );
    if (!saved) return;
    AppSnackbar.show('${contactEntryLabel(_type)} recorded');
    Get.back<void>();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppAppBar(
        title: _args?.contactName == null
            ? 'Add entry'
            : 'Entry for ${_args!.contactName}',
      ),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 120,
          child: Form(
            key: _formKey,
            child: ListView(
              children: <Widget>[
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
                  autofocus: true,
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
                    labelText: 'Amount',
                    prefixText: '${AppFormatters.currencySymbol} ',
                    hintText: '0.00',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppDateField(
                  label: 'Date',
                  value: _date,
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  onChanged: (DateTime d) => setState(() => _date = d),
                ),
                const SizedBox(height: AppSpacing.md),
                AppDateField(
                  label: 'Due date (optional)',
                  value: _dueDate,
                  onChanged: (DateTime d) => setState(() => _dueDate = d),
                  onCleared: () => setState(() => _dueDate = null),
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
                    label: 'Save ${contactEntryLabel(_type).toLowerCase()}',
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
