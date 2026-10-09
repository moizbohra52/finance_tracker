import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Signs out. Sign-out clears this device's copy of the user's data, so
/// changes not yet uploaded would be lost: the user confirms that first.
Future<void> confirmAndSignOut(BuildContext context) async {
  final int pending = Get.isRegistered<SyncEngine>()
      ? Get.find<SyncEngine>().pendingCount.value
      : 0;
  if (pending > 0) {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Discard unsynced changes?',
      message:
          '$pending change${pending == 1 ? ' has' : 's have'} not reached the '
          'server yet. Signing out removes them from this device. Connect to '
          'the internet and let them sync to keep them.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
  }
  await Get.find<AuthController>().signOut();
}
