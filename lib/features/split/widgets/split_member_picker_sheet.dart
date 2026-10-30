import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/contact_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Multi-select for the group form's members. Returns the chosen contact ids,
/// or null when dismissed. "New contact" opens the contact form and reloads
/// the list on return.
Future<List<String>?> pickSplitMembers({
  required List<String> selectedContactIds,
}) async {
  final ContactController contacts = Get.find<ContactController>();
  if (contacts.isLoading.value) await contacts.load(silent: true);
  final Set<String> selected = selectedContactIds.toSet();
  final List<String>? result = await Get.bottomSheet<List<String>>(
    _SplitMemberPickerSheet(selected: selected),
    isScrollControlled: true,
    backgroundColor: Get.theme.colorScheme.surface,
  );
  return result;
}

class _SplitMemberPickerSheet extends StatefulWidget {
  const _SplitMemberPickerSheet({required this.selected});

  final Set<String> selected;

  @override
  State<_SplitMemberPickerSheet> createState() =>
      _SplitMemberPickerSheetState();
}

class _SplitMemberPickerSheetState extends State<_SplitMemberPickerSheet> {
  late final ContactController _contacts = Get.find<ContactController>();
  late final Set<String> _selected = widget.selected.toSet();

  Future<void> _openNewContact() async {
    await Get.toNamed<void>(AppRoutes.contactForm);
    // A new contact may have been added; refresh the list.
    await _contacts.load(silent: true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Choose friends'.tr,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _openNewContact,
                    child: Text('New contact'.tr),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Obx(() {
                if (_contacts.isLoading.value) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: CircularProgressIndicator(),
                  );
                }
                final List<Widget> tiles = <Widget>[
                  for (final ContactBalance tile in _contacts.all)
                    CheckboxListTile(
                      value: _selected.contains(tile.contact.id),
                      title: ContactBalanceTile(row: tile),
                      onChanged: (bool? checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(tile.contact.id);
                        } else {
                          _selected.remove(tile.contact.id);
                        }
                      }),
                    ),
                ];
                if (tiles.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text('No contacts yet'.tr),
                  );
                }
                return ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  children: tiles,
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Get.back<List<String>>(result: <String>[..._selected]),
                  child: Text('Done'.tr),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
