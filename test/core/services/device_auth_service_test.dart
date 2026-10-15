import 'package:finance_tracker/core/services/device_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

/// local_auth answering with [result], or throwing [error].
class _Plugin extends LocalAuthentication {
  _Plugin({this.result = true, this.error});

  final bool result;
  final LocalAuthException? error;
  bool? biometricOnly;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    // Type inferred from the plugin: AuthMessages is not exported.
    authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    this.biometricOnly = biometricOnly;
    final LocalAuthException? failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

Future<DeviceAuthResult> _answer(LocalAuthExceptionCode code) =>
    DeviceAuthService(
      _Plugin(error: LocalAuthException(code: code)),
    ).authenticate('Unlock');

void main() {
  test('a passed check is a success, and the screen lock is accepted', () async {
    final _Plugin plugin = _Plugin();
    expect(
      await DeviceAuthService(plugin).authenticate('Unlock'),
      DeviceAuthResult.success,
    );
    expect(plugin.biometricOnly, isFalse);
  });

  test('a failed check can simply be tried again', () async {
    expect(
      await DeviceAuthService(_Plugin(result: false)).authenticate('Unlock'),
      DeviceAuthResult.cancelled,
    );
    expect(
      await _answer(LocalAuthExceptionCode.userCanceled),
      DeviceAuthResult.cancelled,
    );
    expect(
      await _answer(LocalAuthExceptionCode.systemCanceled),
      DeviceAuthResult.cancelled,
    );
  });

  test('no screen lock on the device is reported as unavailable', () async {
    expect(
      await _answer(LocalAuthExceptionCode.noCredentialsSet),
      DeviceAuthResult.unavailable,
    );
  });

  test('too many attempts are a lockout', () async {
    expect(
      await _answer(LocalAuthExceptionCode.temporaryLockout),
      DeviceAuthResult.lockedOut,
    );
    expect(
      await _answer(LocalAuthExceptionCode.biometricLockout),
      DeviceAuthResult.lockedOut,
    );
  });

  test('anything else is an error, never a crash', () async {
    expect(
      await _answer(LocalAuthExceptionCode.deviceError),
      DeviceAuthResult.error,
    );
  });
}
