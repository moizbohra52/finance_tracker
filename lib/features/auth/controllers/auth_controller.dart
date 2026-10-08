import 'dart:async';

import 'package:finance_tracker/bindings/user_scope.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// App-wide session state. The single place that navigates on auth
/// transitions, so screens only call the repository and never route after
/// sign-in or sign-out themselves.
class AuthController extends GetxController {
  AuthController(this._authRepository);

  final AuthRepository _authRepository;
  StreamSubscription<AuthStatus>? _subscription;

  // Until the splash screen has routed, events are only recorded. The auth
  // stream replays history, so a reset link that cold-started the app can
  // arrive before or after the splash decides; both orders end on the reset
  // screen.
  bool _startupComplete = false;
  bool _recoveryPending = false;

  bool get isSignedIn => _authRepository.isSignedIn;

  /// Signs this device out. AuthController itself then returns to sign-in.
  Future<void> signOut() => _authRepository.signOut();

  @override
  void onInit() {
    super.onInit();
    _subscription = _authRepository.statusChanges.listen(
      _onStatus,
      onError: _onError,
    );
  }

  /// Called once by the splash screen; returns where the app should start.
  String takeStartRoute() {
    _startupComplete = true;
    if (_recoveryPending && isSignedIn) return AppRoutes.resetPassword;
    return isSignedIn ? AppRoutes.dashboard : AppRoutes.onboarding;
  }

  void _onStatus(AuthStatus status) {
    if (!_startupComplete) {
      _recoveryPending = status == AuthStatus.passwordRecovery;
      return;
    }
    switch (status) {
      case AuthStatus.signedIn:
        // Re-authentication inside the app (change password, delete account)
        // also signs in. Preferences reload either way, and only guest screens
        // are left.
        loadUserScope();
        if (AppRoutes.guestOnly.contains(Get.currentRoute)) {
          Get.offAllNamed<void>(AppRoutes.dashboard);
        }
      case AuthStatus.signedOut:
        // Cleared after the sign-in screen replaces the app, so no screen is
        // still reading a controller that is being removed.
        _showSignIn();
      case AuthStatus.passwordRecovery:
        Get.offAllNamed<void>(AppRoutes.resetPassword);
    }
  }

  void _showSignIn() {
    // Not awaited: the returned future completes only when the sign-in screen
    // itself is left, so waiting on it would never reach the reset.
    Get.offAllNamed<void>(AppRoutes.login);
    // The frame that removes the signed-in screens has passed once this runs,
    // so no screen is still reading a controller being removed.
    WidgetsBinding.instance.addPostFrameCallback((_) => resetUserScope());
  }

  void _onError(Object error) {
    AppSnackbar.show(
      error is AppException ? error.message : const UnexpectedFailure().message,
    );
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
