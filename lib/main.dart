import 'dart:async';
import 'dart:developer' as developer;

import 'package:finance_tracker/bindings/initial_binding.dart';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/local_notification_service.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/services/push_service.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/theme/app_accent_color.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/repositories/app_repositories.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/data/repositories/user_settings.dart';
import 'package:finance_tracker/routes/app_pages.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // DateFormat needs symbols for any locale other than en_US.
  await initializeDateFormatting(AppConstants.defaultLocale);
  if (!AppEnv.isConfigured) {
    throw StateError(
      'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are missing. Copy env.example.json '
      'to env.json, fill it in, and run with '
      '--dart-define-from-file=env.json',
    );
  }
  // Restores the persisted session from local storage before the first frame
  // (no network needed), so the splash screen can route immediately.
  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    publishableKey: AppEnv.supabasePublishableKey,
  );
  final SupabaseClient client = Supabase.instance.client;

  // Initialize offline SQLite database
  final AppDatabase database = await AppDatabase.open();
  final ConnectivityService connectivityService = ConnectivityService();
  final DataChangeNotifier dataChangeNotifier = DataChangeNotifier();

  final SyncEngine syncEngine = SyncEngine(
    database: database,
    client: client,
    connectivity: connectivityService,
    notifier: dataChangeNotifier,
  );

  final StorageService storageService = StorageService(
    await SharedPreferences.getInstance(),
  );
  final ThemeController themeController = ThemeController(storageService);
  final AuthRepository authRepository = AuthRepository(client);
  final AppRepositories repositories = AppRepositories.supabase(
    client,
    database: database,
    syncEngine: syncEngine,
  );
  final NotificationCoordinator notificationCoordinator =
      NotificationCoordinator(
        local: LocalNotificationService(),
        push: PushService(),
        repository: repositories.notifications,
        storage: storageService,
        auth: authRepository,
      );

  // Before the first frame, so a notification tap that launched the app is
  // not missed. Notifications are optional: the app runs without them.
  try {
    await notificationCoordinator.initialize();
  } on Object catch (error) {
    developer.log(
      'Notifications could not start: ${error.runtimeType}',
      name: 'notifications',
    );
  }

  // Trigger background sync if online and user is authenticated
  if (authRepository.isSignedIn) {
    unawaited(syncEngine.syncAll());
  }

  runApp(
    FinanceTrackerApp(
      authRepository: authRepository,
      profileRepository: ProfileRepository(
        client,
        database: database,
        syncEngine: syncEngine,
      ),
      userSettingsRepository: UserSettingsRepository(
        client,
        database: database,
        syncEngine: syncEngine,
      ),
      storageService: storageService,
      themeController: themeController,
      connectivityService: connectivityService,
      repositories: repositories,
      notificationCoordinator: notificationCoordinator,
      database: database,
      syncEngine: syncEngine,
      dataChangeNotifier: dataChangeNotifier,
    ),
  );
}

class FinanceTrackerApp extends StatelessWidget {
  FinanceTrackerApp({
    super.key,
    required this.authRepository,
    required this.profileRepository,
    required this.userSettingsRepository,
    required this.storageService,
    required this.themeController,
    required this.connectivityService,
    required this.repositories,
    required this.notificationCoordinator,
    this.database,
    this.syncEngine,
    this.dataChangeNotifier,
  }) : initialBinding = InitialBinding(
         authRepository: authRepository,
         profileRepository: profileRepository,
         userSettingsRepository: userSettingsRepository,
         storageService: storageService,
         themeController: themeController,
         connectivityService: connectivityService,
         repositories: repositories,
         notificationCoordinator: notificationCoordinator,
         database: database,
         syncEngine: syncEngine,
         dataChangeNotifier: dataChangeNotifier,
       );

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final UserSettingsRepository userSettingsRepository;
  final StorageService storageService;
  final ThemeController themeController;
  final ConnectivityService connectivityService;
  final AppRepositories repositories;
  final NotificationCoordinator notificationCoordinator;
  final AppDatabase? database;
  final SyncEngine? syncEngine;
  final DataChangeNotifier? dataChangeNotifier;
  final InitialBinding initialBinding;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final AppAccentColor accent = themeController.accentColor.value;
      return GetMaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightFor(accent.seedColor, variant: accent.variant),
        darkTheme: AppTheme.darkFor(accent.seedColor, variant: accent.variant),
        themeMode: themeController.themeMode.value,
        scaffoldMessengerKey: AppSnackbar.messengerKey,
        initialBinding: initialBinding,
        initialRoute: AppPages.initial,
        getPages: AppPages.routes,
      );
    });
  }
}
