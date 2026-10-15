import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Outcome of asking the user to prove it is them.
enum DeviceAuthResult {
  success,

  /// Dismissed, timed out or interrupted: the user can simply try again.
  cancelled,

  /// The device has no fingerprint, face or screen lock set up.
  unavailable,

  /// Too many failed attempts; the device unlocks it again later.
  lockedOut,

  /// Anything else that went wrong.
  error,
}

/// Thin wrapper over local_auth: the device's own fingerprint or face check,
/// with its PIN, pattern or passcode as the fallback. It makes no decisions;
/// AppLockController decides when to ask.
///
/// Supported on Android and iOS; elsewhere it reports unavailable.
class DeviceAuthService {
  DeviceAuthService([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Whether the device can check the user at all: biometrics, or at least a
  /// screen lock to fall back to.
  Future<bool> isAvailable() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _auth.isDeviceSupported();
    } on Object catch (error) {
      developer.log(
        'Device authentication unavailable: ${error.runtimeType}',
        name: 'app_lock',
      );
      return false;
    }
  }

  Future<DeviceAuthResult> authenticate(String reason) async {
    if (!isSupportedPlatform) return DeviceAuthResult.unavailable;
    try {
      final bool ok = await _auth.authenticate(
        localizedReason: reason,
        // The screen lock is accepted too, so a user whose fingerprint or
        // face is not recognised is never shut out.
        biometricOnly: false,
        // The prompt survives the app being briefly backgrounded.
        persistAcrossBackgrounding: true,
      );
      return ok ? DeviceAuthResult.success : DeviceAuthResult.cancelled;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.authInProgress => DeviceAuthResult.cancelled,
        LocalAuthExceptionCode.noCredentialsSet => DeviceAuthResult.unavailable,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => DeviceAuthResult.lockedOut,
        _ => _failed(error.code.name),
      };
    } on Object catch (error) {
      return _failed(error.runtimeType.toString());
    }
  }

  static DeviceAuthResult _failed(String reason) {
    developer.log('Device authentication failed: $reason', name: 'app_lock');
    return DeviceAuthResult.error;
  }
}
