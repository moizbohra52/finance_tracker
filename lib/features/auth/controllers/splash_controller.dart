import 'dart:async';

import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:get/get.dart';

/// The splash screen holds for a brief moment to show branding before navigating
/// to the appropriate screen based on auth state.
class SplashController extends GetxController {
  SplashController(this._authController);

  final AuthController _authController;

  @override
  void onReady() {
    super.onReady();
    unawaited(_navigateAfterDelay());
  }

  Future<void> _navigateAfterDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    unawaited(Get.offAllNamed<void>(_authController.takeStartRoute()));
  }
}
