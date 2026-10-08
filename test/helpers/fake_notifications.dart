// ignore_for_file: close_sinks
// Fakes live for one test; their stream controllers are never reused.

import 'dart:async';

import 'package:finance_tracker/core/services/local_notification_service.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/services/push_service.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/domain/services/reminder_notification_planner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_finance.dart';

/// In-memory stand-in for the OS notification scheduler. Like the real one it
/// keys scheduled notifications by id, so scheduling an id twice leaves one.
class FakeLocalNotifications implements LocalNotificationService {
  FakeLocalNotifications({
    this.supported = true,
    this.granted = false,
    this.promptGrants = true,
  });

  bool supported;

  /// Whether the OS currently allows notifications.
  bool granted;

  /// What the system prompt does when shown.
  bool promptGrants;

  /// Scheduled notifications by id.
  final Map<int, PlannedNotification> scheduled = <int, PlannedNotification>{};

  /// How many times `replaceSchedule` ran and how many notifications it was
  /// asked to schedule in total, to prove repeat syncs do not pile up.
  int syncCalls = 0;
  int scheduleRequests = 0;

  final List<({int id, String title, String body, String payload})> shown =
      <({int id, String title, String body, String payload})>[];
  int promptCount = 0;
  int settingsOpened = 0;
  int cancelAllCalls = 0;
  bool exactAllowed = true;

  /// Payload of the notification that "launched" the app.
  String? launch;
  void Function(String? payload)? onTap;

  /// Simulates the user tapping a notification.
  void tap(String? payload) => onTap?.call(payload);

  @override
  bool get isSupported => supported;

  @override
  bool get supportsVibrationSetting => supported;

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    this.onTap = onTap;
  }

  @override
  Future<String?> launchPayload() async => launch;

  @override
  Future<void> refreshTimezone() async {}

  @override
  Future<bool> isPermissionGranted() async => supported && granted;

  @override
  Future<bool> requestPermission() async {
    promptCount++;
    granted = promptGrants;
    return granted;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<bool> canScheduleExact() async => exactAllowed;

  @override
  Future<void> requestExactAlarms() async {}

  @override
  Future<void> replaceSchedule(
    List<PlannedNotification> planned, {
    required Set<int> keep,
    required bool sound,
    required bool vibration,
  }) async {
    syncCalls++;
    scheduleRequests += planned.length;
    // Like the OS: entries in `keep` stay as they are, the rest is replaced.
    scheduled
      ..removeWhere((int id, PlannedNotification _) => !keep.contains(id))
      ..addEntries(
        planned.map(
          (PlannedNotification n) =>
              MapEntry<int, PlannedNotification>(n.id, n),
        ),
      );
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required String payload,
    required bool sound,
    required bool vibration,
  }) async {
    shown.add((id: id, title: title, body: body, payload: payload));
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }
}

class FakePush implements PushService {
  FakePush({this.available = false});

  bool available;
  String? currentToken = 'token-1';
  int deletedTokens = 0;
  PushMessage? initial;

  final StreamController<PushMessage> foreground =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> opened =
      StreamController<PushMessage>.broadcast();
  final StreamController<String> refreshes =
      StreamController<String>.broadcast();

  @override
  bool get isAvailable => available;

  @override
  String get platformName => 'android';

  @override
  Future<bool> initialize() async => available;

  @override
  Future<String?> token() async => available ? currentToken : null;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushMessage> get foregroundMessages => foreground.stream;

  @override
  Stream<PushMessage> get openedMessages => opened.stream;

  @override
  Future<PushMessage?> initialMessage() async => initial;

  @override
  Future<void> deleteToken() async => deletedTokens++;
}

/// A coordinator wired to fakes, with the fakes it uses.
typedef NotificationsHandle = ({
  NotificationCoordinator coordinator,
  FakeLocalNotifications local,
  FakePush push,
  StorageService storage,
});

/// Same as [buildCoordinator] for tests that already have a [storage].
NotificationsHandle fakeCoordinator(
  FakeFinance finance, {
  required AuthRepository auth,
  required StorageService storage,
  FakeLocalNotifications? local,
  FakePush? push,
}) {
  final FakeLocalNotifications fakeLocal = local ?? FakeLocalNotifications();
  final FakePush fakePush = push ?? FakePush();
  return (
    coordinator: NotificationCoordinator(
      local: fakeLocal,
      push: fakePush,
      repository: finance.repositories.notifications,
      storage: storage,
      auth: auth,
    ),
    local: fakeLocal,
    push: fakePush,
    storage: storage,
  );
}

Future<NotificationsHandle> buildCoordinator(
  FakeFinance finance, {
  required AuthRepository auth,
  FakeLocalNotifications? local,
  FakePush? push,
  StorageService? storage,
}) async => fakeCoordinator(
  finance,
  auth: auth,
  storage: storage ?? await memoryStorage(),
  local: local,
  push: push,
);

/// A StorageService over an empty in-memory SharedPreferences.
Future<StorageService> memoryStorage() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return StorageService(await SharedPreferences.getInstance());
}
