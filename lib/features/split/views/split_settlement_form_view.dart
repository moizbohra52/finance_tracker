import 'package:finance_tracker/core/theme/app_tokens.dart';
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
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/features/split/controllers/split_settlement_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Arguments of `/split-settlement-form`.
class SplitSettlementArgs {
  const SplitSettlementArgs({
    required this.groupId,
    this.existing,
    this.fromMemberId,
    this.toMemberId,
  });

  final String groupId;
  final SplitSettlement? existing;

  /// Prefills the direction and the outstanding amount.
  final String? fromMemberId;
  final String? toMemberId;
}

/// Settle up: from, to, amount (outstanding prefilled), date, account and
/// note. Delete when editing.
class SplitSettlementFormView extends StatefulWidget {
  const SplitSettlementFormView({super.key});

  @override
  State<SplitSettlementFormView> createState() =>
      _SplitSettlementFormViewState();
}

class _SplitSettlementFormViewState extends State<SplitSettlementFormView> {
  final SplitSettlementController _controller = Get.find();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  DateTime _date = DateTime.now();
  SplitSettlementArgs? _args;

  @override
  void initState() {
    super.initState();
    final Object? arguments = Get.arguments;
    if (arguments is SplitSettlementArgs) {
      _args = arguments;
      _controller
          .start(
            groupId: arguments.groupId,
            existing: arguments.existing,
            fromMemberId: arguments.fromMemberId,
            toMemberId: arguments.toMemberId,
          )
          .then((_) {
            if (!mounted) return;
            _amount.text = _controller.amountText.value;
            final SplitSettlement? existing = arguments.existing;
            if (existing != null) {
              _date = existing.settledAt;
              _note.text = existing.note ?? '';
            }
          });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool ok = await _controller.saveSettlement(
      id: _args?.existing?.id ?? SplitSettlementController.newId(),
      date: _date,
      note: _note.text,
    );
    if (!ok || !mounted) return;
    Get.back<void>();
    AppSnackbar.show(
      _args?.existing == null ? 'Settlement saved'.tr : 'Settlement updated'.tr,
    );
  }

  Future<void> _delete() async {
    final SplitSettlement? existing = _args?.existing;
    if (existing == null) return;
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this settlement?'.tr,
      message: 'The khata entries of this settlement go with it.'.tr,
      confirmLabel: 'Delete'.tr,
    );
    if (!confirmed || !mounted) return;
    final bool ok = await _controller.deleteSettlement(existing.id);
    if (!ok || !mounted) return;
    Get.back<void>();
    AppSnackbar.show('Settlement deleted'.tr);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppAppBar(
        title: _args?.existing == null ? 'Settle up'.tr : 'Edit settlement'.tr,
        actions: <Widget>[
          if (_args?.existing != null)
            IconButton(
              tooltip: 'Delete settlement'.tr,
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: AppContent(
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              Obx(
                () => Row(
                  children: <Widget>[
                    Expanded(
                      child: BottomSheetDropdown<String>(
                        value: _controller.fromId.value,
                        options: <String>[
                          for (final SplitMember m in _controller.members) m.id,
                        ],
                        labelOf: (String id) => _controller.memberNameById(id),
                        decoration: InputDecoration(labelText: 'From'.tr),
                        onChanged: (String? v) =>
                            setState(() => _controller.fromId.value = v),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Icon(Icons.arrow_forward),
                    ),
                    Expanded(
                      child: BottomSheetDropdown<String>(
                        value: _controller.toId.value,
                        options: <String>[
                          for (final SplitMember m in _controller.members)
                            if (m.id != _controller.fromId.value) m.id,
                        ],
                        labelOf: (String id) => _controller.memberNameById(id),
                        decoration: InputDecoration(labelText: 'To'.tr),
                        onChanged: (String? v) =>
                            setState(() => _controller.toId.value = v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Amount'.tr,
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: Validators.positiveAmount,
                onChanged: (String v) => _controller.amountText.value = v,
              ),
              const SizedBox(height: AppSpacing.md),
              AppDateField(
                label: 'Date'.tr,
                value: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                onChanged: (DateTime d) => setState(() => _date = d),
              ),
              const SizedBox(height: AppSpacing.md),
              Obx(() {
                if (!_controller.userIsParty) {
                  return const SizedBox.shrink();
                }
                return BottomSheetDropdown<String>(
                  value: _controller.accountId.value,
                  options: <String>[
                    for (final Account a in _controller.accounts) a.id,
                  ],
                  labelOf: (String id) => _controller.accounts
                      .firstWhere((Account a) => a.id == id)
                      .name,
                  decoration: InputDecoration(labelText: 'Account'.tr),
                  onChanged: (String? v) => _controller.accountId.value = v,
                );
              }),
              const SizedBox(height: AppSpacing.md),
              AppTextField(label: 'Note'.tr, controller: _note),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'From is who paid; to is who received.'.tr,
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SubmitErrorMessage(_controller.save),
              AppButton(
                label: 'Save'.tr,
                icon: Icons.check_rounded,
                onPressed: _save,
                isLoading: _controller.save.isBusy.value,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
