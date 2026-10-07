import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/contact_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Lets the user choose which contact a credit/debit is for. With no
/// contacts yet, it sends them to add one instead.
Future<Contact?> pickContact() async {
  final ContactController controller = Get.find<ContactController>();
  if (controller.isLoading.value) await controller.load(silent: true);
  if (controller.error.value != null) {
    AppSnackbar.show(controller.error.value!);
    return null;
  }
  if (!controller.hasContacts) {
    AppSnackbar.show('Add a contact first, then record a credit or debit.');
    await Get.toNamed<void>(AppRoutes.contactForm);
    return null;
  }
  return Get.bottomSheet<Contact>(
    const _ContactPickerSheet(),
    isScrollControlled: true,
    backgroundColor: Get.theme.colorScheme.surface,
  );
}

class _ContactPickerSheet extends GetView<ContactController> {
  const _ContactPickerSheet();

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
              child: Text(
                'Choose a contact',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: Obx(
                () => ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  children: <Widget>[
                    for (final ContactBalance row in controller.visible)
                      ContactBalanceTile(
                        row: row,
                        onTap: () => Get.back<Contact>(result: row.contact),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
