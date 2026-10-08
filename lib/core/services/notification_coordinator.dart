import 'dart:async';
import 'dart:developer' as developer;

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/local_notification_service.dart';
import 'package:finance_tracker/core/services/notification_permission_state.dart';
import 'package:finance_tracker/core/services/push_service.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/notification_repository.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:finance_tracker/domain/services/reminder_notification_planner.dart';
import 'package:finance_tracker/features/notifications/notification_target.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// The one place that decides what the device is told and where a tap goes.
///
/// * Preferences (device-local) and the permission state are observable.
/// * [syncReminders] makes the device's scheduled notifications match the
///   reminders; it can be called any number of times.
/// * [raise] stores a notification-center entry exactly once and, only the
///   first time, shows it on the device too.
/// * Taps from local notifications and from push messages become a
///   [NotificationTarget] and open once the signed-in shell is on screen.
class NotificationCoordinator extends GetxService {
  NotificationCoordinator({
    required this._local,
    required this._push,
    required this._repository,
    required this._storage,
    required this._auth,
  });

  final LocalNotificationService _local;
  final PushService _push;
  final NotificationRepository _repository;
  final StorageService _storage;
  final AuthRepository _auth;

  static const String _enabledKey = 'notifications.enabled';
  static const String _remindersKey = 'notifications.reminders';
  static const String _budgetsKey = 'notifications.budgets';
  static const String _recurringKey = 'notifications.recurring';
  static const String _soundKey = 'notifications.sound';
  static const String _vibrationKey = 'notifications.vibration';
  static const String _askedKey = 'notifications.permission_asked';
  static const String _deviceIdKey = 'notifications.device_id';

  final Rx<NotificationPreferences> preferences =
      const NotificationPreferences().obs;
  final Rx<NotificationPermissionState> permission =
      NotificationPermissionState.unknown.obs;

  /// Bumped whenever the notification center may have changed (a new entry
  /// was raised, or the app came back to the foreground where pushes may have
  /// added some), so its screen and badge know to re-read.
  final RxInt centerVersion = 0.obs;

  /// False on Android 12+ when exact alarms are withheld: reminders still
  /// fire, possibly a few minutes late.
  final RxBool exactAlarmsAllowed = true.obs;

  bool get isSupported => _local.isSupported;
  bool get supportsVibrationSetting => _local.supportsVibrationSetting;
  bool get pushAvailable => _push.isAvailable;

  List<Reminder> _reminders = <Reminder>[];
  final Set<String> _raisedDue = <String>{};
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  AppLifecycleListener? _lifecycle;
  NotificationTarget? _pendingTarget;
  bool _shellReady = false;
  bool _syncing = false;
  bool _syncAgain = false;

  /// Call once from main(), before the first frame, so a notification that
  /// launched the app is not missed.
  Future<void> initialize() async {
    preferences.value = _loadPreferences();
    await _local.initialize(onTap: _onLocalTap);
    _pendingTarget = NotificationTarget.fromPayload(
      await _local.launchPayload(),
    );
    await refreshPermission();

    if (await _push.initialize()) {
      _subscriptions
        ..add(_push.foregroundMessages.listen(_onForegroundPush))
        ..add(
          _push.openedMessages.listen(
            (PushMessage message) =>
                _open(NotificationTarget.fromData(message.data)),
          ),
        )
        ..add(_push.tokenRefreshes.listen((_) => unawaited(_registerToken())));
      _pendingTarget ??= NotificationTarget.fromData(
        (await _push.initialMessage())?.data ?? const <String, dynamic>{},
      );
    }

    _subscriptions.add(
      _auth.statusChanges.listen(
        _onAuthStatus,
        // Stream errors (an expired email link) are shown by AuthController.
        onError: (Object _) {},
      ),
    );
    _auth.beforeSignOut = _beforeSignOut;
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_onResume()));
    unawaited(_registerToken());
  }

  @override
  void onClose() {
    for (final StreamSubscription<Object?> s in _subscriptions) {
      unawaited(s.cancel());
    }
    _lifecycle?.dispose();
    super.onClose();
  }

  // ---------------------------------------------------------------------
  // Preferences

  NotificationPreferences _loadPreferences() {
    bool flag(String key) => _storage.readBool(key) ?? true;
    return NotificationPreferences(
      enabled: flag(_enabledKey),
      reminders: flag(_remindersKey),
      budgets: flag(_budgetsKey),
      recurring: flag(_recurringKey),
      sound: flag(_soundKey),
      vibration: flag(_vibrationKey),
    );
  }

  /// Saves [next], then applies it. Turning notifications on is the natural
  /// moment to ask for permission, so it asks then (once; see
  /// [requestPermission]). Throws [StorageFailure] when it cannot save.
  Future<void> updatePreferences(NotificationPreferences next) async {
    final NotificationPreferences before = preferences.value;
    await _storage.saveBool(_enabledKey, value: next.enabled);
    await _storage.saveBool(_remindersKey, value: next.reminders);
    await _storage.saveBool(_budgetsKey, value: next.budgets);
    await _storage.saveBool(_recurringKey, value: next.recurring);
    await _storage.saveBool(_soundKey, value: next.sound);
    await _storage.saveBool(_vibrationKey, value: next.vibration);
    preferences.value = next;
    if (next.enabled && !before.enabled && permission.value.canPrompt) {
      await requestPermission();
    }
    await _apply();
  }

  // ---------------------------------------------------------------------
  // Permission

  Future<NotificationPermissionState> refreshPermission() async {
    final bool granted = await _local.isPermissionGranted();
    permission.value = NotificationPermissionState.resolve(
      supported: _local.isSupported,
      granted: granted,
      alreadyAsked: _storage.readBool(_askedKey) ?? false,
    );
    exactAlarmsAllowed.value = await _local.canScheduleExact();
    return permission.value;
  }

  /// Shows the system prompt, at most once. After a refusal this does nothing
  /// and the UI points the user to settings instead ([openSettings]).
  Future<bool> requestPermission() async {
    if (!permission.value.canPrompt) return permission.value.isGranted;
    try {
      await _storage.saveBool(_askedKey, value: true);
    } on AppException catch (error) {
      developer.log(
        'Could not remember the permission prompt: ${error.runtimeType}',
        name: 'notifications',
      );
    }
    await _local.requestPermission();
    await refreshPermission();
    if (permission.value.isGranted) {
      await _apply();
      unawaited(_registerToken());
    }
    return permission.value.isGranted;
  }

  Future<void> openSettings() => _local.openSettings();

  Future<void> openExactAlarmSettings() => _local.requestExactAlarms();

  // ---------------------------------------------------------------------
  // Scheduling and raising

  /// Replaces the device's scheduled reminder notifications with those for
  /// [reminders]. Idempotent: ids are stable, so repeating it never
  /// duplicates, and reminders that were completed, disabled or deleted are
  /// cancelled. Concurrent calls are folded into one more pass.
  Future<void> syncReminders(List<Reminder> reminders) {
    _reminders = List<Reminder>.of(reminders);
    return _apply();
  }

  Future<void> _apply() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        final NotificationPreferences prefs = preferences.value;
        final DateTime now = DateTime.now();
        await _local.replaceSchedule(
          ReminderNotificationPlanner.plan(_reminders, now, prefs),
          keep: ReminderNotificationPlanner.inFlightIds(_reminders, now, prefs),
          sound: prefs.sound,
          vibration: prefs.vibration,
        );
      } while (_syncAgain);
    } on Object catch (error) {
      developer.log(
        'Could not schedule reminder notifications: ${error.runtimeType}',
        name: 'notifications',
      );
    } finally {
      _syncing = false;
    }
  }

  /// Stores a notification-center entry (once per [id], on every device) and,
  /// when this call created it, also shows it on this device. Nothing is
  /// stored when the user turned this kind off. Throws [AppException].
  Future<void> raise({
    required String id,
    required String type,
    required String title,
    required String body,
    required String referenceId,
    bool showOnDevice = true,
  }) async {
    final NotificationPreferences prefs = preferences.value;
    if (!prefs.allows(type)) return;
    final bool created = await _repository.raiseOnce(
      id: id,
      type: type,
      title: title,
      body: body,
      referenceId: referenceId,
    );
    if (created) centerVersion.value++;
    if (created && showOnDevice && permission.value.isGranted) {
      await _local.showNow(
        id: NotificationIds.forEvent(id),
        title: title,
        // Amounts and names stay in the app; the device text is generic.
        body: _deviceBody(type),
        payload: NotificationTarget.payload(type, referenceId),
        sound: prefs.sound,
        vibration: prefs.vibration,
      );
    }
  }

  static String _deviceBody(String type) => switch (type) {
    NotificationType.budgetAlert => 'Open the app to see your budget.',
    NotificationType.recurring => 'Added automatically to your transactions.',
    _ => 'Open the app for details.',
  };

  /// Records, once, that each overdue reminder came due, so it shows up in the
  /// notification center on every device. The device notification itself was
  /// scheduled by [syncReminders], hence no second one here.
  Future<void> raiseDueReminders(List<Reminder> reminders) async {
    final DateTime now = DateTime.now();
    for (final Reminder r in reminders) {
      if (!r.notificationEnabled ||
          ReminderCalculator.status(r, now) != ReminderStatus.overdue) {
        continue;
      }
      final String eventId = NotificationIds.dueEventId(r);
      if (!_raisedDue.add(eventId)) continue;
      try {
        await raise(
          id: eventId,
          type: NotificationType.reminder,
          title: r.title,
          body: ReminderNotificationPlanner.bodyFor(r.type),
          referenceId: r.id,
          showOnDevice: false,
        );
      } on AppException {
        // Best effort: forget it so the next load retries.
        _raisedDue.remove(eventId);
      }
    }
  }

  // ---------------------------------------------------------------------
  // Taps and deep links

  void _onLocalTap(String? payload) =>
      _open(NotificationTarget.fromPayload(payload));

  void _open(NotificationTarget? target) {
    if (target == null) return;
    if (_shellReady) {
      _go(target);
    } else {
      // Cold start or signed out: wait for the signed-in shell.
      _pendingTarget = target;
    }
  }

  void _go(NotificationTarget target) =>
      Get.toNamed<void>(target.route, arguments: target.argument);

  /// The signed-in shell is on screen: open whatever tap launched the app.
  void markShellReady() {
    _shellReady = true;
    final NotificationTarget? target = _pendingTarget;
    _pendingTarget = null;
    if (target != null) _go(target);
  }

  void markShellGone() => _shellReady = false;

  // ---------------------------------------------------------------------
  // Push

  /// FCM shows nothing while the app is open, so show it as a local
  /// notification. Messages without text (data-only) are ignored.
  void _onForegroundPush(PushMessage message) {
    final NotificationPreferences prefs = preferences.value;
    final String? title = message.title;
    if (title == null || !prefs.enabled || !permission.value.isGranted) {
      return;
    }
    final Object? type = message.data['type'];
    final Object? id = message.data['reference_id'];
    unawaited(
      _local.showNow(
        id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
        title: title,
        body: message.body ?? '',
        payload: type is String
            ? NotificationTarget.payload(type, id is String ? id : null)
            : NotificationType.recurring,
        sound: prefs.sound,
        vibration: prefs.vibration,
      ),
    );
  }

  String _deviceId() {
    final String? stored = _storage.readString(_deviceIdKey);
    if (stored != null) return stored;
    final String created = const Uuid().v4();
    unawaited(
      _storage.saveString(_deviceIdKey, created).catchError((Object error) {
        developer.log(
          'Could not store the device id: ${error.runtimeType}',
          name: 'notifications',
        );
      }),
    );
    return created;
  }

  /// Sends this install's FCM token to the server so it can push to it.
  Future<void> _registerToken() async {
    if (!_push.isAvailable ||
        !_auth.isSignedIn ||
        !preferences.value.enabled ||
        !permission.value.isGranted) {
      return;
    }
    final String? token = await _push.token();
    if (token == null) return;
    try {
      await _repository.registerDeviceToken(
        token: token,
        platform: _push.platformName,
        deviceId: _deviceId(),
      );
    } on AppException catch (error) {
      developer.log(
        'Device token not registered: ${error.runtimeType}',
        name: 'notifications',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Session and lifecycle

  void _onAuthStatus(AuthStatus status) {
    switch (status) {
      case AuthStatus.signedIn:
        unawaited(_registerToken());
      case AuthStatus.signedOut:
        // The next user must not receive this user's reminders.
        _reminders = <Reminder>[];
        _raisedDue.clear();
        _pendingTarget = null;
        _shellReady = false;
        unawaited(_local.cancelAll());
      case AuthStatus.passwordRecovery:
        break;
    }
  }

  /// Runs while the session is still valid, so the server can be told to stop
  /// pushing to this install.
  Future<void> _beforeSignOut() async {
    if (!_push.isAvailable) return;
    try {
      await _repository.deactivateDeviceToken(_deviceId());
    } on AppException catch (error) {
      developer.log(
        'Device token not deactivated: ${error.runtimeType}',
        name: 'notifications',
      );
    }
    await _push.deleteToken();
  }

  /// Back from the background: permission may have changed in system
  /// settings, and the time zone may have changed while away.
  Future<void> _onResume() async {
    centerVersion.value++;
    await _local.refreshTimezone();
    await refreshPermission();
    await _apply();
    unawaited(_registerToken());
  }
}
