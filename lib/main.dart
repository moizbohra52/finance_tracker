import 'package:finance_tracker/bindings/initial_binding.dart';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/routes/app_pages.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final StorageService storageService = StorageService(
    await SharedPreferences.getInstance(),
  );
  final ThemeController themeController = ThemeController(storageService);

  runApp(
    FinanceTrackerApp(
      authRepository: AuthRepository(client),
      profileRepository: ProfileRepository(client),
      storageService: storageService,
      themeController: themeController,
      connectivityService: ConnectivityService(),
    ),
  );
}

class FinanceTrackerApp extends StatelessWidget {
  FinanceTrackerApp({
    super.key,
    required this.authRepository,
    required this.profileRepository,
    required this.storageService,
    required this.themeController,
    required this.connectivityService,
  }) : initialBinding = InitialBinding(
         authRepository: authRepository,
         profileRepository: profileRepository,
         storageService: storageService,
         themeController: themeController,
         connectivityService: connectivityService,
       );

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final StorageService storageService;
  final ThemeController themeController;
  final ConnectivityService connectivityService;
  final InitialBinding initialBinding;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final Color accentSeed = themeController.accentColor.value.seedColor;
      return GetMaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightFor(accentSeed),
        darkTheme: AppTheme.darkFor(accentSeed),
        themeMode: themeController.themeMode.value,
        scaffoldMessengerKey: AppSnackbar.messengerKey,
        initialBinding: initialBinding,
        initialRoute: AppPages.initial,
        getPages: AppPages.routes,
      );
    });
  }
}
