import 'package:finance_tracker/bindings/initial_binding.dart';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/routes/app_pages.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  runApp(
    FinanceTrackerApp(
      authRepository: AuthRepository(client),
      profileRepository: ProfileRepository(client),
    ),
  );
}

class FinanceTrackerApp extends StatelessWidget {
  const FinanceTrackerApp({
    super.key,
    required this.authRepository,
    required this.profileRepository,
  });

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // ThemeController starts at system too; it switches modes via
      // Get.changeThemeMode, which rebuilds this app with the new mode.
      themeMode: ThemeMode.system,
      scaffoldMessengerKey: AppSnackbar.messengerKey,
      initialBinding: InitialBinding(
        authRepository: authRepository,
        profileRepository: profileRepository,
      ),
      initialRoute: AppPages.initial,
      getPages: AppPages.routes,
    );
  }
}
