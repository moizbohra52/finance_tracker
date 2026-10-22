import 'dart:async';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/services/notification_permission_state.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Explains why reminders may not alert the user and offers the one action
/// that fixes it: turn notifications on, allow them, or open system settings.
/// It is a passive banner on the screens that need notifications, never a
/// pop-up, so a refusal is not nagged about. Shows nothing when everything is
/// in order or the platform has no notifications.
class NotificationPermissionBanner extends StatelessWidget {
  const NotificationPermissionBanner({super.key});

  Future<void> _turnOn(NotificationCoordinator coordinator) async {
    try {
      await coordinator.updatePreferences(
        coordinator.preferences.value.copyWith(enabled: true),
      );
    } on AppException catch (failure) {
      AppSnackbar.show(failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NotificationCoordinator coordinator =
        Get.find<NotificationCoordinator>();
    return Obx(() {
      final NotificationPermissionState state = coordinator.permission.value;
      final bool enabled = coordinator.preferences.value.enabled;
      if (state == NotificationPermissionState.unsupported ||
          state == NotificationPermissionState.unknown) {
        return const SizedBox.shrink();
      }
      final ({String message, String action, VoidCallback onTap})? content =
          !enabled
          ? (
              message:
                  'Notifications are turned off, so reminders will not alert you.'
                      .tr,
              action: 'Turn on'.tr,
              onTap: () => unawaited(_turnOn(coordinator)),
            )
          : state.canPrompt
          ? (
              message:
                  'Allow notifications so reminders can alert you on time.'.tr,
              action: 'Allow'.tr,
              onTap: () => unawaited(coordinator.requestPermission()),
            )
          : state.needsSettings
          ? (
              message:
                  'Notifications are blocked for this app. Turn them on in your device settings to get reminders.'
                      .tr,
              action: 'Open settings'.tr,
              onTap: () => unawaited(coordinator.openSettings()),
            )
          : null;
      if (content == null) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: InlineMessage(
          tone: InlineMessageTone.notice,
          icon: Icons.notifications_off_outlined,
          message: content.message,
          action: TextButton(
            onPressed: content.onTap,
            child: Text(content.action),
          ),
        ),
      );
    });
  }
}
