import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:get/get.dart';

/// App-wide dependencies, registered once at startup. Screen-level
/// dependencies are bound on their route in routes/app_pages.dart.
class InitialBinding extends Bindings {
  InitialBinding({
    required this.authRepository,
    required this.profileRepository,
  });

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;

  @override
  void dependencies() {
    Get.put(ThemeController(), permanent: true);
    Get.put(authRepository, permanent: true);
    Get.put(profileRepository, permanent: true);
    Get.put(AuthController(authRepository), permanent: true);
  }
}
