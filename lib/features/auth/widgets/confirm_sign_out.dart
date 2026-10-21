import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/widgets/app_dialog.dart';
import 'package:finance_tracker/domain/entities/saved_login.dart';
import 'package:finance_tracker/features/auth/controllers/account_switch_controller.dart';
import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Signs the active account out. Sign-out clears this device's copy of the
/// account's data, so changes not yet uploaded would be lost: the user
/// confirms that first. Another signed-in account, if any, takes over.
Future<void> confirmAndSignOut(BuildContext context) async {
  final int pending = Get.isRegistered<SyncEngine>()
      ? Get.find<SyncEngine>().pendingCount.value
      : 0;
  final SavedLogin? next = Get.isRegistered<AccountSwitchController>()
      ? Get.find<AccountSwitchController>().nextAfterSignOut
      : null;

  final String title = pending > 0
      ? 'Discard unsynced changes?'.tr
      : 'Sign Out'.tr;
  final Map<String, String> count = <String, String>{'count': '$pending'};
  final String message = pending == 0
      ? 'Are you sure you want to sign out of your account?'.tr
      : pending == 1
      ? '@count change has not reached the server yet. Signing out removes them from this device. Connect to the internet and let them sync to keep them.'
            .trParams(count)
      : '@count changes have not reached the server yet. Signing out removes them from this device. Connect to the internet and let them sync to keep them.'
            .trParams(count);
  final String switchNote = next == null
      ? ''
      : '\n\n${'You will switch to @name (@email).'.trParams(<String, String>{'name': next.label, 'email': next.email})}';

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AppDialog(
      title: title,
      icon: const Icon(Icons.logout_rounded),
      content: Text('$message$switchNote'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Sign out'.tr),
        ),
      ],
    ),
  );

  if (confirmed != true) return;
  final String? activeId = Get.isRegistered<AccountSwitchController>()
      ? Get.find<AccountSwitchController>().activeUserId
      : null;
  await Get.find<AuthController>().signOut(activeId);
}
