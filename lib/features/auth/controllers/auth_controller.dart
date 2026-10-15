import 'dart:async';

import 'package:finance_tracker/bindings/user_scope.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/features/auth/controllers/account_switch_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:get/get.dart';

/// App-wide session state. The single place that reacts to auth
/// transitions, so screens only call the repository and never route after
/// sign-in or sign-out themselves. What happens to the account itself (its
/// database file, another signed-in account taking over at sign-out) is
/// AccountSwitchController's part.
class AuthController extends GetxController {
  AuthController(this._authRepository, this._accounts);

  final AuthRepository _authRepository;
  final AccountSwitchController _accounts;
  StreamSubscription<AuthStatus>? _subscription;

  // Until the splash screen has routed, events are only recorded. The auth
  // stream replays history, so a reset link that cold-started the app can
  // arrive before or after the splash decides; both orders end on the reset
  // screen.
  bool _startupComplete = false;
  bool _recoveryPending = false;

  bool get isSignedIn => _authRepository.isSignedIn;

  /// Signs the active account out of this device. AuthController itself then
  /// moves on (to another signed-in account, or to sign-in).
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
        unawaited(_onSignedIn());
      case AuthStatus.signedOut:
        // Shows another signed-in account or the sign-in screen, and clears
        // the signed-out account's data once its screens are gone.
        unawaited(_accounts.handleSignedOut());
      case AuthStatus.passwordRecovery:
        Get.offAllNamed<void>(AppRoutes.resetPassword);
    }
  }

  /// Re-authentication inside the app (change password, delete account) also
  /// signs in. Preferences reload either way, and only guest screens are
  /// left. The account's database is opened before anything reads it.
  Future<void> _onSignedIn() async {
    await _accounts.handleSignedIn();
    loadUserScope();
    if (AppRoutes.guestOnly.contains(Get.currentRoute)) {
      unawaited(Get.offAllNamed<void>(AppRoutes.dashboard));
    }
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
