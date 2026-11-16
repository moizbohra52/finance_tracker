import 'dart:async';
import 'dart:developer' as developer;

import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/dashboard/views/dashboard_view.dart';
import 'package:get/get.dart';
import 'package:quick_actions/quick_actions.dart';

/// The app icon's long-press shortcuts. They open the same forms as the home
/// screen's quick actions, and only while [isShellActive]: a shortcut that
/// launched the app signed out opens once the user signs in.
Future<void> setUpAppShortcuts({required bool Function() isShellActive}) async {
  const QuickActions shortcuts = QuickActions();
  try {
    await shortcuts.setShortcutItems(<ShortcutItem>[
      ShortcutItem(type: 'expense', localizedTitle: 'Add expense'.tr),
      ShortcutItem(type: 'income', localizedTitle: 'Add income'.tr),
      ShortcutItem(type: 'khata', localizedTitle: 'Khata entry'.tr),
    ]);
    await shortcuts.initialize((String type) {
      if (!isShellActive()) return;
      switch (type) {
        case 'expense':
          addTransaction(TransactionType.expense);
        case 'income':
          addTransaction(TransactionType.income);
        case 'khata':
          unawaited(addKhataEntry(ContactTransactionType.credit));
      }
    });
  } on Object catch (error) {
    // Tests and platforms without the plugin; the app works without them.
    developer.log('Unavailable: ${error.runtimeType}', name: 'shortcuts');
  }
}
