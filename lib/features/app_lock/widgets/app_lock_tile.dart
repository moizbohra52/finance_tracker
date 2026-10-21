import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/features/app_lock/controllers/app_lock_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Settings switch for app lock. Changing it asks for the fingerprint, face
/// or screen lock first. Hidden where the platform has no such check.
class AppLockTile extends GetView<AppLockController> {
  const AppLockTile({super.key});

  Future<void> _change(bool value) async {
    final String? message = await controller.setEnabled(value: value);
    if (message != null) AppSnackbar.show(message);
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported) return const SizedBox.shrink();
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Obx(
      () => AppListTile(
        leading: IconBadge(
          icon: Icons.fingerprint_rounded,
          color: colors.primary,
        ),
        title: 'App lock'.tr,
        subtitle:
            'Ask for fingerprint, face or screen lock every time the app opens'
                .tr,
        subtitleMaxLines: 2,
        trailing: Switch(
          value: controller.enabled.value,
          onChanged: controller.busy.value ? null : _change,
        ),
        onTap: controller.busy.value
            ? null
            : () => _change(!controller.enabled.value),
      ),
    );
  }
}
