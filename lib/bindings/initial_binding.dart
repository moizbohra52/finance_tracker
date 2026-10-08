import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/app_repositories.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/budget_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/notification_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/data/repositories/recurring_repository.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/data/repositories/user_settings.dart';
import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:get/get.dart';

/// App-wide dependencies, registered once at startup. Screen-level
/// dependencies are bound on their route in routes/app_pages.dart.
class InitialBinding extends Bindings {
  InitialBinding({
    required this.authRepository,
    required this.profileRepository,
    required this.userSettingsRepository,
    required this.storageService,
    required this.themeController,
    required this.connectivityService,
    required this.repositories,
    required this.notificationCoordinator,
  });

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final UserSettingsRepository userSettingsRepository;
  final StorageService storageService;
  final ThemeController themeController;
  final ConnectivityService connectivityService;
  final AppRepositories repositories;
  final NotificationCoordinator notificationCoordinator;

  @override
  void dependencies() {
    final DataChangeNotifier notifier = DataChangeNotifier();
    Get.put<StorageService>(storageService, permanent: true);
    Get.put<ThemeController>(themeController, permanent: true);
    Get.put<ConnectivityService>(connectivityService, permanent: true);
    Get.put<AuthRepository>(authRepository, permanent: true);
    Get.put<ProfileRepository>(profileRepository, permanent: true);
    Get.put<UserSettingsRepository>(userSettingsRepository, permanent: true);
    Get.put(AuthController(authRepository), permanent: true);
    Get.put<AccountRepository>(repositories.accounts, permanent: true);
    Get.put<CategoryRepository>(repositories.categories, permanent: true);
    Get.put<TransactionRepository>(repositories.transactions, permanent: true);
    Get.put<ContactRepository>(repositories.contacts, permanent: true);
    Get.put<BudgetRepository>(repositories.budgets, permanent: true);
    Get.put<RecurringRepository>(repositories.recurring, permanent: true);
    Get.put<NotificationRepository>(
      repositories.notifications,
      permanent: true,
    );
    Get.put<ReminderRepository>(repositories.reminders, permanent: true);
    Get.put<NotificationCoordinator>(notificationCoordinator, permanent: true);
    Get.put<DataChangeNotifier>(notifier, permanent: true);
    Get.put<SettingsController>(
      SettingsController(
        profileRepository,
        userSettingsRepository,
        repositories.accounts,
        authRepository,
        notifier,
      ),
      permanent: true,
    );
  }
}
