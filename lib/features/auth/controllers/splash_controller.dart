import 'dart:async';

import 'package:finance_tracker/features/auth/controllers/account_switch_controller.dart';
import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:get/get.dart';

/// The splash screen holds for a brief moment to show branding before navigating
/// to the appropriate screen based on auth state.
class SplashController extends GetxController {
  SplashController(this._authController, this._accounts);

  final AuthController _authController;
  final AccountSwitchController _accounts;

  @override
  void onReady() {
    super.onReady();
    unawaited(_navigateAfterDelay());
  }

  Future<void> _navigateAfterDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final String route = _authController.takeStartRoute();
    // The last active account's session ended while the app was closed, but
    // other accounts are still signed in: one of them takes over.
    if (!_authController.isSignedIn && _accounts.canResume) {
      unawaited(_accounts.resumeSaved());
      return;
    }
    unawaited(Get.offAllNamed<void>(route));
  }
}
