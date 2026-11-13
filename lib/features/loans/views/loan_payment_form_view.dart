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
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/features/loans/controllers/loan_payment_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Records a payment on a loan (an EMI, a prepayment or the closing payment),
/// or edits the one in [LoanPaymentArgs.existing]. The amount is split into
/// principal and interest by the controller; either part can be corrected.
class LoanPaymentFormView extends StatefulWidget {
  const LoanPaymentFormView({super.key});

  @override
  State<LoanPaymentFormView> createState() => _LoanPaymentFormViewState();
}

class _LoanPaymentFormViewState extends State<LoanPaymentFormView> {
  final LoanPaymentController _controller = Get.find<LoanPaymentController>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _principal = TextEditingController();
  final TextEditingController _interest = TextEditingController();
  final TextEditingController _note = TextEditingController();

  late final LoanPaymentArgs _args;
  final List<Worker> _follows = <Worker>[];

  @override
  void initState() {
    super.initState();
    _args = LoanPaymentArgs.of(Get.arguments);
    _controller.save.error.value = null;
    // The controller fills and re-splits the three amounts; a field is only
    // written when its text differs, so typing never moves the cursor.
    for (final (RxString rx, TextEditingController field)
        in <(RxString, TextEditingController)>[
          (_controller.amountText, _amount),
          (_controller.principalText, _principal),
          (_controller.interestText, _interest),
        ]) {
      _follows.add(
        ever<String>(rx, (String text) {
          if (field.text != text) field.text = text;
        }),
      );
    }
    unawaited(_start());
  }

  /// Loads the loan and the accounts; the form shows a skeleton or the load
  /// error until then. The note is the only field the controller leaves to
  /// the view.
  Future<void> _start() async {
    await _controller.start(_args);
    if (!mounted) return;
    _note.text = _controller.note.value;
  }

  @override
  void dispose() {
    for (final Worker w in _follows) {
      w.dispose();
    }
    _amount.dispose();
    _principal.dispose();
    _interest.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bool ok = await _controller.savePayment();
    if (!ok || !mounted) return;
    Get.back<void>();
    AppSnackbar.show(
      _args.existing == null ? 'Payment saved'.tr : 'Payment updated'.tr,
    );
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this payment?'.tr,
      message: 'Its transactions are removed too.'.tr,
      confirmLabel: 'Delete'.tr,
    );
    if (!confirmed || !mounted) return;
    if (!await _controller.deletePayment() || !mounted) return;
    Get.back<void>();
    AppSnackbar.show('Payment deleted'.tr);
  }

  String get _title {
    if (_args.existing != null) return 'Edit payment'.tr;
    if (_args.closing) return 'Close loan'.tr;
    return _args.kind == LoanPaymentKind.extra
        ? 'Prepay'.tr
        : 'Record payment'.tr;
  }

  String _accountName(String id) {
    for (final Account a in _controller.accounts) {
      if (a.id == id) return a.name;
    }
    return 'Account'.tr;
  }

  @override
  Widget build(BuildContext context) {
    const TextInputType decimal = TextInputType.numberWithOptions(
      decimal: true,
    );
    final bool editing = _args.existing != null;

    return Scaffold(
      appBar: AppAppBar(
        title: _title,
        actions: <Widget>[
          if (editing)
            IconButton(
              tooltip: 'Delete payment'.tr,
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Obx(() {
          final String? loadError = _controller.loadError.value;
          if (loadError != null) {
            return LoadFailureView(message: loadError, onRetry: _start);
          }
          if (_controller.loan.value == null) {
            return const AppContent(
              child: SkeletonList(count: 4, type: SkeletonType.budget),
            );
          }
          return AppContent(
            child: ListView(
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xxl,
              ),
              children: <Widget>[
                const SizedBox(height: AppSpacing.xs),
                AppDateField(
                  label: 'Date'.tr,
                  value: _controller.paidAt.value,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  onChanged: _controller.setDate,
                ),
                const SizedBox(height: AppSpacing.md),
                BottomSheetDropdown<String>(
                  value: _controller.accountId.value,
                  options: <String>[
                    for (final Account a in _controller.accounts) a.id,
                  ],
                  labelOf: _accountName,
                  decoration: InputDecoration(labelText: 'Account'.tr),
                  onChanged: (String? v) => _controller.accountId.value = v,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Amount'.tr,
                  controller: _amount,
                  keyboardType: decimal,
                  textInputAction: TextInputAction.next,
                  onChanged: _controller.setAmount,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Principal'.tr,
                  controller: _principal,
                  keyboardType: decimal,
                  textInputAction: TextInputAction.next,
                  onChanged: _controller.setPrincipal,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Interest'.tr,
                  controller: _interest,
                  keyboardType: decimal,
                  textInputAction: TextInputAction.next,
                  onChanged: _controller.setInterest,
                ),
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
