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
    return Obx(
      () => SwitchListTile(
        secondary: const Icon(Icons.fingerprint_rounded),
        title: const Text('App lock'),
        subtitle: const Text(
          'Ask for fingerprint, face or screen lock every time the app opens',
        ),
        value: controller.enabled.value,
        onChanged: controller.busy.value ? null : _change,
      ),
    );
  }
}
