import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/features/split/controllers/split_group_controller.dart';
import 'package:finance_tracker/features/split/widgets/split_member_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The group form: name and members. Create, edit and delete.
class SplitGroupFormView extends StatefulWidget {
  const SplitGroupFormView({super.key});

  @override
  State<SplitGroupFormView> createState() => _SplitGroupFormViewState();
}

class _SplitGroupFormViewState extends State<SplitGroupFormView> {
  final SplitGroupController _controller = Get.find<SplitGroupController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();

  /// The chosen friends; kept in state so the chips update while typing.
  final RxSet<String> _selected = <String>{}.obs;
  SplitGroupSummary? _existing;

  @override
  void initState() {
    super.initState();
    final Object? arguments = Get.arguments;
    if (arguments is SplitGroupSummary) {
      _existing = arguments;
      _name.text = arguments.group.name;
      _controller.membersOf(arguments.group.id).then((
        List<SplitMember> members,
      ) {
        if (!mounted) return;
        _selected.addAll(<String>[
          for (final SplitMember m in members)
            if (!m.isMe && m.contactId != null) m.contactId!,
        ]);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addFriends() async {
    final List<String>? picked = await pickSplitMembers(
      selectedContactIds: _selected.toList(),
    );
    if (picked != null) {
      _selected
        ..clear()
        ..addAll(picked);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final String groupId = _existing?.group.id ?? SplitGroupController.newId();
    final bool ok = await _controller.saveGroup(
      groupId: groupId,
      name: _name.text,
      friendContactIds: _selected.toList(),
    );
    if (!ok || !mounted) return;
    Get.back<void>();
    AppSnackbar.show(
      _existing == null ? 'Group created'.tr : 'Group updated'.tr,
    );
  }

  Future<void> _delete() async {
    final SplitGroupSummary? existing = _existing;
    if (existing == null) return;
    final ({int expenses, int khataEntries}) impact = await _controller
        .deleteImpact(existing.group.id);
    if (!mounted) return;
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this group?'.tr,
      message: 'This deletes @expenses expenses and @entries khata entries.'
          .trParams(<String, String>{
            'expenses': '${impact.expenses}',
            'entries': '${impact.khataEntries}',
          }),
      confirmLabel: 'Delete group'.tr,
    );
    if (!confirmed || !mounted) return;
    final bool ok = await _controller.deleteGroup(existing.group.id);
    if (!ok || !mounted) return;
    Get.back<void>();
    AppSnackbar.show('Group deleted'.tr);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppAppBar(
        title: _existing == null ? 'New group'.tr : 'Edit group'.tr,
        actions: <Widget>[
          if (_existing != null)
            IconButton(
              tooltip: 'Delete group'.tr,
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
              AppTextField(
                label: 'Group name'.tr,
                controller: _name,
                autofocus: _existing == null,
                validator: (String? v) => (v == null || v.trim().isEmpty)
                    ? 'Give the group a name'.tr
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  Expanded(child: Text('Members'.tr, style: text.titleSmall)),
                  TextButton.icon(
                    onPressed: _addFriends,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text('Add friends'.tr),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Obx(() {
                if (_selected.isEmpty) {
                  return Text(
                    'Add at least one friend'.tr,
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final String contactId in _selected)
                      InputChip(
                        label: Text(_controller.contactName(contactId)),
                        onDeleted: () => _selected.remove(contactId),
                      ),
                  ],
                );
              }),
              const SizedBox(height: AppSpacing.lg),
              SubmitErrorMessage(_controller.save),
              AppButton(
                label: 'Save'.tr,
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
