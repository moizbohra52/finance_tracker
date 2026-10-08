import 'dart:async';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/features/notifications/widgets/notification_permission_banner.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Notification preferences: the master switch, which kinds to receive, and
/// sound and vibration. Platform limits are respected: vibration is hidden
/// where the OS decides it, and the whole section explains itself on
/// platforms without notifications.
class NotificationSettingsSection extends StatelessWidget {
  const NotificationSettingsSection({super.key});

  Future<void> _change(
    NotificationCoordinator coordinator,
    NotificationPreferences next,
  ) async {
    try {
      await coordinator.updatePreferences(next);
    } on AppException catch (failure) {
      AppSnackbar.show(failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NotificationCoordinator coordinator =
        Get.find<NotificationCoordinator>();
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Notifications', style: text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (!coordinator.isSupported)
          const AppCard(
            child: Text(
              'Notifications are not available on this device. Reminders are '
              'still saved and shown in the app.',
            ),
          )
        else ...<Widget>[
          const NotificationPermissionBanner(),
          Obx(() {
            final NotificationPreferences prefs = coordinator.preferences.value;
            Widget tile(
              String title,
              String subtitle,
              bool value,
              NotificationPreferences Function(bool) next, {
              bool enabled = true,
            }) => SwitchListTile(
              title: Text(title),
              subtitle: Text(subtitle),
              value: value,
              onChanged: enabled
                  ? (bool v) => unawaited(_change(coordinator, next(v)))
                  : null,
            );
            return AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  tile(
                    'Notifications',
                    'Turn all notifications on or off',
                    prefs.enabled,
                    (bool v) => prefs.copyWith(enabled: v),
                  ),
                  tile(
                    'Reminders',
                    'Alert me when a reminder is due',
                    prefs.reminders,
                    (bool v) => prefs.copyWith(reminders: v),
                    enabled: prefs.enabled,
                  ),
                  tile(
                    'Budget alerts',
                    'When spending reaches 75%, 90% or 100% of a budget',
                    prefs.budgets,
                    (bool v) => prefs.copyWith(budgets: v),
                    enabled: prefs.enabled,
                  ),
                  tile(
                    'Recurring transactions',
                    'When a recurring transaction is recorded',
                    prefs.recurring,
                    (bool v) => prefs.copyWith(recurring: v),
                    enabled: prefs.enabled,
                  ),
                  tile(
                    'Sound',
                    'Play a sound with notifications',
                    prefs.sound,
                    (bool v) => prefs.copyWith(sound: v),
                    enabled: prefs.enabled,
                  ),
                  if (coordinator.supportsVibrationSetting)
                    tile(
                      'Vibration',
                      'Vibrate with notifications',
                      prefs.vibration,
                      (bool v) => prefs.copyWith(vibration: v),
                      enabled: prefs.enabled,
                    ),
                ],
              ),
            );
          }),
          Obx(
            () => coordinator.exactAlarmsAllowed.value
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: AppCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.alarm_on_outlined),
                        title: const Text('Exact reminder times'),
                        subtitle: const Text(
                          'Without this, reminders can arrive a few minutes '
                          'late.',
                        ),
                        trailing: TextButton(
                          onPressed: () =>
                              unawaited(coordinator.openExactAlarmSettings()),
                          child: const Text('Allow'),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}
