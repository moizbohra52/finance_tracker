import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/budget_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/notification_repository.dart';
import 'package:finance_tracker/data/repositories/recurring_repository.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/features/accounts/controllers/account_detail_controller.dart';
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
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_detail_controller.dart';
import 'package:get/get.dart';

/// Registers [create] unless a screen further down the stack already did, so
/// a controller shared by a tab and a pushed route is created only once.
void _putIfAbsent<T extends GetxController>(T Function() create) {
  if (!Get.isRegistered<T>()) Get.lazyPut<T>(create);
}

/// The route argument as an id, e.g. a contact or transaction id.
String _idArgument() => Get.arguments is String ? Get.arguments as String : '';

class TransactionBinding extends Bindings {
  @override
  void dependencies() => _putIfAbsent(
    () => TransactionController(
      Get.find<TransactionRepository>(),
      Get.find<AccountRepository>(),
      Get.find<CategoryRepository>(),
      Get.find<DataChangeNotifier>(),
    ),
  );
}

class TransactionDetailBinding extends Bindings {
  @override
  void dependencies() {
    TransactionBinding().dependencies();
    Get.put<TransactionDetailController>(
      TransactionDetailController(
        Get.find<TransactionRepository>(),
        Get.find<DataChangeNotifier>(),
        _idArgument(),
      ),
    );
  }
}

class ContactBinding extends Bindings {
  @override
  void dependencies() {
    _putIfAbsent(
      () => ContactController(
        Get.find<ContactRepository>(),
        Get.find<DataChangeNotifier>(),
      ),
    );
    _putIfAbsent(
      () => ContactFormController(
        Get.find<ContactRepository>(),
        Get.find<DataChangeNotifier>(),
      ),
    );
  }
}

class ContactDetailBinding extends Bindings {
  @override
  void dependencies() {
    ContactBinding().dependencies();
    Get.put<ContactDetailController>(
      ContactDetailController(
        Get.find<ContactRepository>(),
        Get.find<DataChangeNotifier>(),
        _idArgument(),
      ),
    );
  }
}

class AccountBinding extends Bindings {
  @override
  void dependencies() => _putIfAbsent(
    () => AccountController(
      Get.find<AccountRepository>(),
      Get.find<TransactionRepository>(),
      Get.find<DataChangeNotifier>(),
    ),
  );
}

class AccountDetailBinding extends Bindings {
  @override
  void dependencies() {
    AccountBinding().dependencies();
    TransactionBinding().dependencies();
    Get.put<AccountDetailController>(
      AccountDetailController(
        Get.find<AccountRepository>(),
        Get.find<TransactionRepository>(),
        Get.find<DataChangeNotifier>(),
        _idArgument(),
      ),
    );
  }
}

class ReportsBinding extends Bindings {
  @override
  void dependencies() => _putIfAbsent(
    () => ReportsController(
      Get.find<AccountRepository>(),
      Get.find<TransactionRepository>(),
      Get.find<ContactRepository>(),
      Get.find<CategoryRepository>(),
      Get.find<DataChangeNotifier>(),
    ),
  );
}

class BudgetBinding extends Bindings {
  @override
  void dependencies() => _putIfAbsent(
    () => BudgetController(
      Get.find<BudgetRepository>(),
      Get.find<TransactionRepository>(),
      Get.find<CategoryRepository>(),
      Get.find<NotificationCoordinator>(),
      Get.find<DataChangeNotifier>(),
    ),
  );
}

class RecurringBinding extends Bindings {
  @override
  void dependencies() => _putIfAbsent(
    () => RecurringController(
      Get.find<RecurringRepository>(),
      Get.find<TransactionRepository>(),
      Get.find<AccountRepository>(),
      Get.find<CategoryRepository>(),
      Get.find<NotificationCoordinator>(),
      Get.find<DataChangeNotifier>(),
    ),
  );
}

class ReminderBinding extends Bindings {
  @override
  void dependencies() => _putIfAbsent(
    () => ReminderController(
      Get.find<ReminderRepository>(),
      Get.find<ContactRepository>(),
      Get.find<NotificationCoordinator>(),
      Get.find<DataChangeNotifier>(),
    ),
  );
}

class NotificationCenterBinding extends Bindings {
  @override
  void dependencies() => _putIfAbsent(
    () => NotificationCenterController(
      Get.find<NotificationRepository>(),
      Get.find<NotificationCoordinator>(),
    ),
  );
}

/// Everything the signed-in shell's tabs need.
class ShellBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ProfileController>(
      () => ProfileController(Get.find(), Get.find()),
      fenix: true,
    );
    _putIfAbsent(
      () => HomeController(
        Get.find<AccountRepository>(),
        Get.find<TransactionRepository>(),
        Get.find<ContactRepository>(),
        Get.find<CategoryRepository>(),
        Get.find<DataChangeNotifier>(),
      ),
    );
    TransactionBinding().dependencies();
    ContactBinding().dependencies();
    AccountBinding().dependencies();
    ReportsBinding().dependencies();
    // Created right away (not on first visit): the recurring controller turns
    // due schedules into transactions and the budget controller raises
    // threshold alerts, both of which must happen without opening their
    // screens.
    BudgetBinding().dependencies();
    RecurringBinding().dependencies();
    Get.find<BudgetController>();
    Get.find<RecurringController>();
    // Same for reminders (they schedule the device notifications) and the
    // notification center (it owns the unread badge in the app bar).
    ReminderBinding().dependencies();
    NotificationCenterBinding().dependencies();
    Get.find<ReminderController>();
    Get.find<NotificationCenterController>();
  }
}
