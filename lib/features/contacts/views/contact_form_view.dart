import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Add a contact, or edit one passed as the route argument.
class ContactFormView extends StatefulWidget {
  const ContactFormView({super.key});

  @override
  State<ContactFormView> createState() => _ContactFormViewState();
}

class _ContactFormViewState extends State<ContactFormView> {
  final ContactFormController _controller = Get.find<ContactFormController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _mobile = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _opening = TextEditingController(text: '0');

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = ContactFormController.newId();
  late final Contact? _existing;
  String _openingType = 'receivable';

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    _existing = args is Contact ? args : null;
    final Contact? c = _existing;
    if (c != null) {
      _name.text = c.name;
      _mobile.text = c.mobile ?? '';
      _email.text = c.email ?? '';
      _address.text = c.address ?? '';
      _notes.text = c.notes ?? '';
      _opening.text = c.openingBalance.toString();
      _openingType = c.openingBalanceType;
    }
    _controller.save.error.value = null;
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name,
      _mobile,
      _email,
      _address,
      _notes,
      _opening,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _orNull(TextEditingController c) {
    final String v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool saved = await _controller.saveContact(
      id: _existing?.id ?? _id,
      existing: _existing,
      name: _name.text.trim(),
      mobile: _orNull(_mobile),
      email: _orNull(_email),
      address: _orNull(_address),
      notes: _orNull(_notes),
      openingBalance: Decimal.parse(_opening.text.trim()),
      openingBalanceType: _openingType,
    );
    if (!saved) return;
    AppSnackbar.show(_existing == null ? 'Contact added' : 'Contact updated');
    Get.back<void>();
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = _existing != null;
    return Scaffold(
      appBar: AppAppBar(title: editing ? 'Edit contact' : 'Add contact'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 120,
          child: Form(
            key: _formKey,
            child: ListView(
              children: <Widget>[
                AppTextField(
                  label: 'Name',
                  controller: _name,
                  autofocus: !editing,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) => Validators.name(v, 'a name'),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Mobile (optional)',
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: Validators.optionalMobile,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Email (optional)',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      (v ?? '').trim().isEmpty ? null : Validators.email(v),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Address (optional)',
                  controller: _address,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Notes (optional)',
                  controller: _notes,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Opening balance',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'receivable',
                      label: Text('They owe me'),
                    ),
                    ButtonSegment<String>(
                      value: 'payable',
                      label: Text('I owe them'),
                    ),
                  ],
                  selected: <String>{_openingType},
                  onSelectionChanged: (Set<String> s) =>
                      setState(() => _openingType = s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Opening amount',
                  controller: _opening,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  helperText: 'What was already owed before you started here.',
                  validator: Validators.nonNegativeAmount,
                ),
                const SizedBox(height: AppSpacing.lg),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: editing ? 'Save changes' : 'Add contact',
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
