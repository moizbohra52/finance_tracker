import 'dart:async';

import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_bottom_sheet_dropdown.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/features/contacts/views/contact_picker_sheet.dart';
import 'package:finance_tracker/features/loans/controllers/loan_form_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Add a loan, or edit the one in [LoanFormArgs.existing]. Once the loan has
/// a payment only the name, contact and note can change.
class LoanFormView extends StatefulWidget {
  const LoanFormView({super.key});

  @override
  State<LoanFormView> createState() => _LoanFormViewState();
}

class _LoanFormViewState extends State<LoanFormView> {
  final LoanFormController _controller = Get.find<LoanFormController>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _principal = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _tenure = TextEditingController();
  final TextEditingController _emi = TextEditingController();
  final TextEditingController _note = TextEditingController();

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = LoanFormController.newId();
  late final LoanFormArgs _args;
  late final Worker _emiFollows;

  @override
  void initState() {
    super.initState();
    final Object? arguments = Get.arguments;
    _args = arguments is LoanFormArgs ? arguments : const LoanFormArgs();
    _controller.save.error.value = null;
    // The controller fills the EMI from the principal, rate and tenure.
    _emiFollows = ever<String>(_controller.emiText, (String text) {
      if (_emi.text != text) _emi.text = text;
    });
    unawaited(_start());
  }

  /// Loads the pickers and, for an edit, the loan; fills the text fields once
  /// it is there (the form shows a skeleton or the load error until then).
  Future<void> _start() async {
    await _controller.start(_args);
    if (!mounted ||
        _args.existing == null ||
        _controller.loadError.value != null) {
      return;
    }
    _name.text = _controller.name.value;
    _principal.text = _controller.principalText.value;
    _rate.text = _controller.rateText.value;
    _tenure.text = _controller.tenureText.value;
    _emi.text = _controller.emiText.value;
    _note.text = _controller.note.value;
  }

  @override
  void dispose() {
    _emiFollows.dispose();
    _name.dispose();
    _principal.dispose();
    _rate.dispose();
    _tenure.dispose();
    _emi.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _chooseContact() async {
    final Contact? picked = await pickContact();
    if (picked != null) _controller.contactId.value = picked.id;
  }

  Future<void> _save() async {
    final bool ok = await _controller.saveLoan(_args.existing?.id ?? _id);
    if (!ok || !mounted) return;
    Get.back<void>();
    AppSnackbar.show(
      _args.existing == null ? 'Loan added'.tr : 'Loan updated'.tr,
    );
  }

  /// The account's name; a safe label when it is not in the list (an edit of
  /// a loan whose account was deleted).
  String _accountName(String id) {
    for (final Account a in _controller.accounts) {
      if (a.id == id) return a.name;
    }
    return 'Account'.tr;
  }

  String? _contactName(String? id) {
    for (final Contact c in _controller.contacts) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = _args.existing != null;
    final TextTheme text = Theme.of(context).textTheme;
    const TextInputType decimal = TextInputType.numberWithOptions(
      decimal: true,
    );

    return Scaffold(
      appBar: AppAppBar(title: editing ? 'Edit loan'.tr : 'Add loan'.tr),
      body: SafeArea(
        child: Obx(() {
          if (_controller.isLoading.value) {
            return const AppContent(
              child: SkeletonList(count: 4, type: SkeletonType.budget),
            );
          }
          final String? loadError = _controller.loadError.value;
          if (loadError != null) {
            return LoadFailureView(message: loadError, onRetry: _start);
          }
          return AppContent(
            maxWidth: AppSizes.maxContentWidth + 120,
            child: ListView(
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xxl,
              ),
              children: <Widget>[
                const SizedBox(height: AppSpacing.xs),
                Obx(() {
                  final bool locked = _controller.termsLocked.value;
                  final bool isEmi = _controller.method.value == LoanMethod.emi;
                  final bool taken =
                      _controller.direction.value == LoanDirection.taken;
                  final String? contactName = _contactName(
                    _controller.contactId.value,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (locked) ...<Widget>[
                        InlineMessage(
                          tone: InlineMessageTone.info,
                          announce: false,
                          message:
                              'Terms are locked after the first payment'.tr,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _Lockable(
                            locked: locked,
                            child: SegmentedButton<LoanDirection>(
                              segments: <ButtonSegment<LoanDirection>>[
                                ButtonSegment<LoanDirection>(
                                  value: LoanDirection.taken,
                                  label: Text('Taken'.tr),
                                ),
                                ButtonSegment<LoanDirection>(
                                  value: LoanDirection.given,
                                  label: Text('Given'.tr),
                                ),
                              ],
                              selected: <LoanDirection>{
                                _controller.direction.value,
                              },
                              // The direction is fixed once the loan exists.
                              onSelectionChanged: editing || locked
                                  ? null
                                  : (Set<LoanDirection> s) =>
                                        _controller.direction.value = s.first,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _Lockable(
                            locked: locked,
                            child: SegmentedButton<LoanMethod>(
                              segments: <ButtonSegment<LoanMethod>>[
                                ButtonSegment<LoanMethod>(
                                  value: LoanMethod.emi,
                                  label: Text('EMI'.tr),
                                ),
                                ButtonSegment<LoanMethod>(
                                  value: LoanMethod.monthlyInterest,
                                  label: Text('Monthly interest'.tr),
                                ),
                              ],
                              selected: <LoanMethod>{_controller.method.value},
                              onSelectionChanged: locked
                                  ? null
                                  : (Set<LoanMethod> s) =>
                                        _controller.method.value = s.first,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: 'Loan name'.tr,
                        hintText: 'e.g. HDFC Home Loan'.tr,
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        onChanged: (String v) => _controller.name.value = v,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: _chooseContact,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Contact (optional)'.tr,
                            suffixIcon: contactName == null
                                ? const Icon(Icons.person_search_outlined)
                                : IconButton(
                                    tooltip: 'Clear contact'.tr,
                                    icon: const Icon(Icons.close),
                                    onPressed: () =>
                                        _controller.contactId.value = null,
                                  ),
                          ),
                          child: Text(
                            contactName ?? 'Not set'.tr,
                            style: text.bodyLarge,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: 'Principal'.tr,
                        controller: _principal,
                        enabled: !locked,
                        keyboardType: decimal,
                        textInputAction: TextInputAction.next,
                        onChanged: (String v) =>
                            _controller.principalText.value = v,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: isEmi
                            ? 'Interest rate (% a year)'.tr
                            : 'Interest rate (% a month)'.tr,
                        controller: _rate,
                        enabled: !locked,
                        keyboardType: decimal,
                        textInputAction: TextInputAction.next,
                        onChanged: (String v) => _controller.rateText.value = v,
                      ),
                      if (isEmi) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        AppTextField(
                          label: 'Tenure (months)'.tr,
                          controller: _tenure,
                          enabled: !locked,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onChanged: (String v) =>
                              _controller.tenureText.value = v,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppTextField(
                          label: 'EMI'.tr,
                          helperText:
                              'Filled from the amount, rate and tenure. Change it to match your bank.'
                                  .tr,
                          controller: _emi,
                          enabled: !locked,
                          keyboardType: decimal,
                          textInputAction: TextInputAction.next,
                          onChanged: _controller.editEmi,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _Lockable(
                        locked: locked,
                        child: AppDateField(
                          label: 'Start date'.tr,
                          value: _controller.startDate.value,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          onChanged: (DateTime d) =>
                              _controller.startDate.value = d,
                        ),
                      ),
                      if (isEmi) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        _Lockable(
                          locked: locked,
                          child: AppDateField(
                            label: 'First EMI date'.tr,
                            value: _controller.firstDueDate.value,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            onChanged: (DateTime d) =>
                                _controller.firstDueDate.value = d,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _Lockable(
                        locked: locked,
                        child: BottomSheetDropdown<String>(
                          value: _controller.accountId.value,
                          options: <String>[
                            for (final Account a in _controller.accounts) a.id,
                          ],
                          labelOf: _accountName,
                          decoration: InputDecoration(labelText: 'Account'.tr),
                          onChanged: (String? v) =>
                              _controller.accountId.value = v,
                        ),
                      ),
                      _Lockable(
                        locked: locked,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            taken
                                ? 'Money came into this account'.tr
                                : 'Money went out of this account'.tr,
                          ),
                          subtitle: Text(
                            'Turn off if the loan is older than your records.'
                                .tr,
                          ),
                          value: _controller.movedMoney.value,
                          onChanged: locked
                              ? null
                              : (bool v) => _controller.movedMoney.value = v,
                        ),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Note'.tr,
                  controller: _note,
                  maxLines: 3,
                  minLines: 1,
                  onChanged: (String v) => _controller.note.value = v,
                ),
                const SizedBox(height: AppSpacing.lg),
                Obx(() {
                  final String? error = _controller.error;
                  return error == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: InlineMessage(message: error.tr),
                        );
                }),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: 'Save'.tr,
                    icon: Icons.check_rounded,
                    isLoading: _controller.save.isBusy.value,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Greys out a picker when [locked] and takes it out of touch, focus and the
/// accessibility tree's enabled state: the date, account and switch widgets
/// have no `enabled` of their own.
class _Lockable extends StatelessWidget {
  const _Lockable({required this.locked, required this.child});

  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      excluding: locked,
      child: IgnorePointer(
        ignoring: locked,
        child: Semantics(
          enabled: locked ? false : null,
          child: Opacity(opacity: locked ? 0.5 : 1, child: child),
        ),
      ),
    );
  }
}
