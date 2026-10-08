import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/features/accounts/controllers/account_detail_controller.dart';
import 'package:finance_tracker/features/auth/controllers/change_password_controller.dart';
import 'package:finance_tracker/features/auth/controllers/forgot_password_controller.dart';
import 'package:finance_tracker/features/auth/controllers/login_controller.dart';
import 'package:finance_tracker/features/auth/controllers/register_controller.dart';
import 'package:finance_tracker/features/auth/controllers/reset_password_controller.dart';
import 'package:finance_tracker/features/budgets/controllers/budget_controller.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:finance_tracker/features/contacts/controller/contact_detail_controller.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/features/dashboard/controllers/home_controller.dart';
import 'package:finance_tracker/features/notifications/controllers/notification_center_controller.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/recurring/controllers/recurring_controller.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:finance_tracker/features/reports/controllers/reports_controller.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_detail_controller.dart';
import 'package:get/get.dart';

/// Loads the signed-in user's preferences. Called on every sign-in, so the
/// first screen formats with that user's values.
void loadUserScope() {
  if (Get.isRegistered<SettingsController>()) {
    Get.find<SettingsController>().load();
  }
}

/// Clears everything that belongs to the user who just signed out: their
/// preferences and every controller that holds their data or typed passwords.
/// Global infrastructure (repositories, the notifier, the notification
/// coordinator, storage) is not touched.
///
/// Settings are reset, not removed, because they are global. Everything else
/// is removed, so the next user gets fresh controllers that load their own
/// data. Call it after the sign-in screen is showing, so no screen is still
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
  // Detail and form screens.
  _remove<AccountController>,
  _remove<AccountDetailController>,
  _remove<ContactFormController>,
  _remove<ContactDetailController>,
  _remove<TransactionDetailController>,
  // Auth screens, which hold typed passwords.
  _remove<LoginController>,
  _remove<RegisterController>,
  _remove<ForgotPasswordController>,
  _remove<ResetPasswordController>,
  _remove<ChangePasswordController>,
];
