import 'dart:async';

import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/features/auth/controllers/add_account_controller.dart';
import 'package:finance_tracker/features/auth/controllers/change_password_controller.dart';
import 'package:finance_tracker/features/auth/controllers/forgot_password_controller.dart';
import 'package:finance_tracker/features/auth/controllers/login_controller.dart';
import 'package:finance_tracker/features/auth/controllers/register_controller.dart';
import 'package:finance_tracker/features/auth/controllers/reset_password_controller.dart';
import 'package:finance_tracker/features/budgets/controllers/budget_controller.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/features/dashboard/controllers/home_controller.dart';
import 'package:finance_tracker/features/notifications/controllers/notification_center_controller.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/recurring/controllers/recurring_controller.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:finance_tracker/features/reports/controllers/reports_controller.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:get/get.dart';

/// Loads the active account's preferences and starts a sync, which pulls
/// whatever its local database does not have yet. Called on every sign-in
/// and account switch, so the first screen formats with that account's
/// values.
void loadUserScope() {
  if (Get.isRegistered<SettingsController>()) {
    Get.find<SettingsController>().load();
  }
  if (Get.isRegistered<SyncEngine>()) {
    unawaited(Get.find<SyncEngine>().syncAll());
  }
}

/// Clears what the app holds in memory for the account that is no longer
/// active (signed out, or switched away from): its preferences and every
/// controller that holds its data or typed passwords. Global infrastructure
/// (repositories, the notifier, the notification coordinator, storage) is not
/// touched, and neither is the local database: AccountSwitchController
/// decides what happens to the account's file.
///
/// Settings are reset, not removed, because they are global. Everything else
/// is removed, so the next account gets fresh controllers that load their own
/// data. Call it after the signed-in screens are gone, so no screen is still
/// reading a controller being removed.
void resetUserScope() {
  if (Get.isRegistered<SettingsController>()) {
    Get.find<SettingsController>().reset();
  }
  for (final void Function() remove in _userScopedRemovers) {
    remove();
  }
}

void _remove<T extends GetxController>() {
  if (Get.isRegistered<T>()) Get.delete<T>(force: true);
}

final List<void Function()> _userScopedRemovers = <void Function()>[
  // Tabs and the shell.
  _remove<HomeController>,
  _remove<TransactionController>,
  _remove<ContactController>,
  _remove<ReportsController>,
  _remove<ProfileController>,
  // Planning and notifications.
  _remove<BudgetController>,
  _remove<RecurringController>,
  _remove<ReminderController>,
  _remove<NotificationCenterController>,
  // Form screens. Detail controllers are tagged per record (see
  // routeIdArgument) and go with their routes when sign-out clears the stack.
  _remove<AccountController>,
  _remove<ContactFormController>,
  // Auth screens, which hold typed passwords.
  _remove<LoginController>,
  _remove<RegisterController>,
  _remove<ForgotPasswordController>,
  _remove<ResetPasswordController>,
  _remove<ChangePasswordController>,
  _remove<AddAccountController>,
];
