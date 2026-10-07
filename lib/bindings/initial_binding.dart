import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App-wide dependencies, registered once at startup. Screen-level
/// dependencies are bound on their route in routes/app_pages.dart.
class InitialBinding extends Bindings {
  InitialBinding({
    required this.authRepository,
    required this.profileRepository,
    required this.storageService,
    required this.themeController,
    required this.connectivityService,
  });

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final StorageService storageService;
  final ThemeController themeController;
  final ConnectivityService connectivityService;

  @override
  void dependencies() {
    Get.put<StorageService>(storageService, permanent: true);
    Get.put<ThemeController>(themeController, permanent: true);
    Get.put<ConnectivityService>(connectivityService, permanent: true);
    Get.put<AuthRepository>(authRepository, permanent: true);
    Get.put<ProfileRepository>(profileRepository, permanent: true);
    Get.put(AuthController(authRepository), permanent: true);
    // Account repository
    final SupabaseClient client = Supabase.instance.client;
    Get.put<AccountRepository>(AccountRepository(client), permanent: true);
  }
}