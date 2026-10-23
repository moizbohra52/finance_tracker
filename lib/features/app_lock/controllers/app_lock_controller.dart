import 'dart:async';
import 'dart:developer' as developer;

import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/device_auth_service.dart';
import 'package:finance_tracker/core/services/external_activity.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// App lock: when the user turns it on, the app opens only after the
/// device's own fingerprint or face check (or its screen lock as fallback).
///
/// * Locked at start and every time the app goes to the background, while an
///   account is signed in. Coming back within [externalGrace] from a screen
///   the app opened itself (photo picker, share sheet, settings; see
///   [ExternalActivity]) does not lock.
/// * The lock is a cover over the whole app (AppLockGate), not a route, so a
///   tapped notification still opens its screen underneath, hidden until the
///   user unlocks. The back button leaves the app instead of reaching it.
/// * A device-wide preference, like the notification settings: one lock for
///   every account signed in on the device.
class AppLockController extends GetxService with WidgetsBindingObserver {
  AppLockController({
    required this._deviceAuth,
    required this._storage,
    required this._auth,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DeviceAuthService _deviceAuth;
  final StorageService _storage;
  final AuthRepository _auth;
  final DateTime Function() _clock;

  static const String _enabledKey = 'security.app_lock';

  /// How long the user may stay in a screen the app opened before coming
  /// back asks to unlock.
  static const Duration externalGrace = Duration(minutes: 2);

  final RxBool enabled = false.obs;
  final RxBool locked = false.obs;

  /// The device's prompt is showing.
  final RxBool busy = false.obs;

  /// Why the last unlock did not work, for the lock screen.
  final RxnString lockMessage = RxnString();

  AppLifecycleListener? _lifecycle;
  DateTime? _hiddenAt;
  bool _hiddenForExternal = false;
  bool _hasPrompted = false;

  bool get isSupported => _deviceAuth.isSupportedPlatform;

  /// Call once from main(), before runApp: the back button must reach the
  /// lock before the app's navigator, so this observer has to be first.
  void initialize() {
    if (_lifecycle != null) return;
    enabled.value = isSupported && (_storage.readBool(_enabledKey) ?? false);
    locked.value = enabled.value && _auth.isSignedIn;
    _lifecycle = AppLifecycleListener(
      onHide: _onHide,
      onShow: _onShow,
      onResume: _promptIfVisible,
    );
    WidgetsBinding.instance
      ..addObserver(this)
      // A cold start: ask as soon as the first frame (the cover) is up.
      ..addPostFrameCallback((_) => _promptIfVisible());
  }

  /// Stops listening; the counterpart of [initialize].
  void detach() {
    _lifecycle?.dispose();
    _lifecycle = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void onClose() {
    detach();
    super.onClose();
  }

  // ---------------------------------------------------------------------
  // Locking and unlocking

  /// Asks for the device's check and opens the app when it passes.
  Future<void> unlock() async {
    if (!locked.value || busy.value) return;
    busy.value = true;
    _hasPrompted = true;
    lockMessage.value = null;
    try {
      final DeviceAuthResult result = await _deviceAuth.authenticate(
        'Unlock @app'.trParams(<String, String>{'app': AppConstants.appName}),
      );
      switch (result) {
        case DeviceAuthResult.success:
          locked.value = false;
          _hasPrompted = false;
          lockMessage.value = null;
        case DeviceAuthResult.unavailable:
          // The device has no screen lock any more. Removing it needed the
          // old one, so the lock protects nothing now: turn it off rather
          // than shut the user out of their data.
          await _save(false);
          locked.value = false;
          _hasPrompted = false;
          AppSnackbar.show(
            'App lock was turned off because this device no longer has a screen lock.'
                .tr,
          );
        case DeviceAuthResult.lockedOut:
        case DeviceAuthResult.error:
          lockMessage.value = _messageFor(result);
        case DeviceAuthResult.cancelled:
          lockMessage.value = 'Tap Unlock to try again.'.tr;
      }
    } finally {
      busy.value = false;
    }
  }

  /// Turns app lock on or off, after the user proves it is them. Returns a
  /// message to show when it did not change, or null.
  Future<String?> setEnabled({required bool value}) async {
    if (value == enabled.value || busy.value) return null;
    if (value && !await _deviceAuth.isAvailable()) {
      return _messageFor(DeviceAuthResult.unavailable);
    }
    busy.value = true;
    try {
      final DeviceAuthResult result = await _deviceAuth.authenticate(
        value
            ? 'Confirm to turn on app lock'.tr
            : 'Confirm to turn off app lock'.tr,
      );
      // Turning it off on a device without a screen lock needs no proof:
      // the lock cannot work there anyway.
      final bool allowed =
          result == DeviceAuthResult.success ||
          (!value && result == DeviceAuthResult.unavailable);
      if (!allowed) return _messageFor(result);
      await _storage.saveBool(_enabledKey, value: value);
      enabled.value = value;
      return null;
    } on AppException catch (error) {
      return error.message;
    } finally {
      busy.value = false;
    }
  }

  static String? _messageFor(DeviceAuthResult result) => switch (result) {
    DeviceAuthResult.success || DeviceAuthResult.cancelled => null,
    DeviceAuthResult.unavailable =>
      'Set up a fingerprint, face, PIN or pattern lock on this device first.'
          .tr,
    DeviceAuthResult.lockedOut =>
      'Too many attempts. Unlock your phone once, then try again.'.tr,
    DeviceAuthResult.error =>
      'Your fingerprint or face could not be checked. Please try again.'.tr,
  };

  Future<void> _save(bool value) async {
    enabled.value = value;
    try {
      await _storage.saveBool(_enabledKey, value: value);
    } on AppException catch (error) {
      developer.log(
        'App lock setting not saved: ${error.runtimeType}',
        name: 'app_lock',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Lifecycle

  void _onHide() {
    // The device's own PIN screen hides the app while the prompt runs.
    if (busy.value) return;
    _hiddenAt = _clock();
    _hiddenForExternal = ExternalActivity.isActive;
    // Locked while still on screen, so the app switcher shows the cover.
    if (!_hiddenForExternal) _lock();
  }

  void _onShow() {
    if (busy.value) return;
    final DateTime? hiddenAt = _hiddenAt;
    if (_hiddenForExternal &&
        hiddenAt != null &&
        _clock().difference(hiddenAt) >= externalGrace) {
      _lock();
    }
    _hiddenAt = null;
    _hiddenForExternal = false;
  }

  void _lock() {
    if (enabled.value && _auth.isSignedIn) {
      locked.value = true;
      _hasPrompted = false;
      lockMessage.value = null;
    }
  }

  /// The prompt needs the app in the foreground; when it is not, the next
  /// resume asks instead. Only auto-prompts once per lock session.
  void _promptIfVisible() {
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    if (locked.value && !_hasPrompted && !busy.value) {
      unawaited(unlock());
    }
  }

  @override
  Future<bool> didPopRoute() async {
    if (!locked.value) return false;
    // Like the device's own lock screen: back leaves the app.
    await SystemNavigator.pop();
    return true;
  }
}
