import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:finance_tracker/bindings/initial_binding.dart';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/device_auth_service.dart';
import 'package:finance_tracker/core/services/local_notification_service.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/services/push_service.dart';
import 'package:finance_tracker/core/services/reminder_action_handler.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/theme/app_accent_color.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/datasources/local/saved_login_store.dart';
import 'package:finance_tracker/data/repositories/app_repositories.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/data/repositories/user_settings.dart';
import 'package:finance_tracker/features/app_lock/controllers/app_lock_controller.dart';
import 'package:finance_tracker/features/app_lock/widgets/app_lock_gate.dart';
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
      '[AppEnv] Supabase credentials missing for [${AppEnv.current.name.toUpperCase()}] environment.\n'
      'Please check your env.${AppEnv.current.name}.json or provide '
      'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.',
    );
  }
  developer.log(
    'Starting ${AppConstants.appName} | Environment: [${AppEnv.current.name.toUpperCase()}] | Local DB: ${AppEnv.databaseName}',
    name: 'AppEnv',
  );
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final String? lastEnv = preferences.getString('app.last_env');
  final String currentEnv = AppEnv.current.name;

  if (lastEnv != null && lastEnv != currentEnv) {
    developer.log(
      'Environment switch detected: [$lastEnv] -> [$currentEnv]. '
      'Sanitizing foreign session to prevent data/auth conflicts.',
      name: 'AppEnv',
    );
    await _sanitizeEnvironmentStorage(preferences);
  }
  await preferences.setString('app.last_env', currentEnv);

  // Restores the persisted session from local storage before the first frame
  // (no network needed), so the splash screen can route immediately.
  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    publishableKey: AppEnv.supabasePublishableKey,
  );
  final SupabaseClient client = Supabase.instance.client;

  // Extra guard: If Supabase still restored a session from a foreign URL, clear it locally.
  final Session? restored = client.auth.currentSession;
  if (restored != null &&
      !_isSessionValidForEnv(restored.accessToken, AppEnv.supabaseUrl)) {
    developer.log(
      'Foreign Supabase session detected at startup. Clearing local session.',
      name: 'AppEnv',
    );
    await client.auth.signOut(scope: SignOutScope.local);
  }

  // The signed-in account's own database file (each signed-in account has
  // one; see AccountSwitchController).
  final AppDatabase database = await AppDatabase.open(
    userId: client.auth.currentUser?.id,
  );
  final ConnectivityService connectivityService = ConnectivityService();
  final DataChangeNotifier dataChangeNotifier = DataChangeNotifier();

  final SyncEngine syncEngine = SyncEngine(
    database: database,
    client: client,
    connectivity: connectivityService,
    notifier: dataChangeNotifier,
  );

  final StorageService storageService = StorageService(preferences);
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

  // A Mark done / Snooze on a notification changed a reminder in the
  // background: reload what is on screen and send the change.
  listenForReminderActions(() {
    dataChangeNotifier.markChanged();
    syncEngine.notifyNewQueueItem();
  });

  // Before runApp, so its back-button handling comes before the navigator's
  // and a locked cold start shows the lock from the first frame.
  final AppLockController appLock = AppLockController(
    deviceAuth: DeviceAuthService(),
    storage: storageService,
    auth: authRepository,
  )..initialize();

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
      savedLogins: SavedLoginStore(preferences),
      themeController: themeController,
      connectivityService: connectivityService,
      repositories: repositories,
      notificationCoordinator: notificationCoordinator,
      appLock: appLock,
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
    required this.savedLogins,
    required this.themeController,
    required this.connectivityService,
    required this.repositories,
    required this.notificationCoordinator,
    required this.appLock,
    this.database,
    this.syncEngine,
    this.dataChangeNotifier,
  }) : initialBinding = InitialBinding(
         authRepository: authRepository,
         profileRepository: profileRepository,
         userSettingsRepository: userSettingsRepository,
         storageService: storageService,
         savedLogins: savedLogins,
         themeController: themeController,
         connectivityService: connectivityService,
         repositories: repositories,
         notificationCoordinator: notificationCoordinator,
         appLock: appLock,
         database: database,
         syncEngine: syncEngine,
         dataChangeNotifier: dataChangeNotifier,
       );

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final UserSettingsRepository userSettingsRepository;
  final StorageService storageService;
  final SavedLoginStore savedLogins;
  final ThemeController themeController;
  final ConnectivityService connectivityService;
  final AppRepositories repositories;
  final NotificationCoordinator notificationCoordinator;
  final AppLockController appLock;
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
        theme: AppTheme.lightFor(accent),
        darkTheme: AppTheme.darkFor(accent),
        themeMode: themeController.themeMode.value,
        scaffoldMessengerKey: AppSnackbar.messengerKey,
        initialBinding: initialBinding,
        initialRoute: AppPages.initial,
        getPages: AppPages.routes,
        builder: (BuildContext context, Widget? child) =>
            AppLockGate(controller: appLock, child: child),
      );
    });
  }
}

/// Validates that an access token was issued by the target Supabase URL.
bool _isSessionValidForEnv(String? accessToken, String targetUrl) {
  if (accessToken == null || accessToken.isEmpty) return true;
  try {
    final List<String> parts = accessToken.split('.');
    if (parts.length < 2) return true;
    final String normalized = base64Url.normalize(parts[1]);
    final String payloadJson = utf8.decode(base64Url.decode(normalized));
    final Object? payload = jsonDecode(payloadJson);
    if (payload is! Map<String, dynamic>) return true;
    final Object? iss = payload['iss'];
    if (iss is! String || iss.isEmpty) return true;
    final Uri? issUri = Uri.tryParse(iss);
    final Uri? targetUri = Uri.tryParse(targetUrl);
    if (issUri != null && targetUri != null && issUri.host.isNotEmpty) {
      return issUri.host.toLowerCase() == targetUri.host.toLowerCase();
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Cleans up foreign environment sessions from SharedPreferences when switching
/// between dev (debug) and prod (release) builds on the same device.
Future<void> _sanitizeEnvironmentStorage(SharedPreferences preferences) async {
  final Set<String> keys = preferences.getKeys();
  for (final String key in keys) {
    if (key == 'supabase.auth.token' ||
        (key.startsWith('sb-') && key.endsWith('-auth-token'))) {
      final String? raw = preferences.getString(key);
      if (raw != null) {
        try {
          final Object? decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            final Object? token = decoded['access_token'];
            if (token is String &&
                !_isSessionValidForEnv(token, AppEnv.supabaseUrl)) {
              await preferences.remove(key);
            }
          }
        } catch (_) {
          await preferences.remove(key);
        }
      }
    }
  }
}

