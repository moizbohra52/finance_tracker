import 'dart:developer' as developer;

import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:finance_tracker/domain/services/reminder_notification_planner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:get/get.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper over flutter_local_notifications: initialisation, permission,
/// scheduling and cancelling. It makes no decisions; what to schedule comes
/// from ReminderNotificationPlanner and who may be notified from the
/// preferences, both applied by NotificationCoordinator.
///
/// Supported on Android and iOS. Everywhere else every method is a no-op that
/// reports "unsupported", so desktop and web builds still run.
class LocalNotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const String _androidIcon = 'ic_stat_notification';
  static bool _zonesLoaded = false;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Whether the OS has a per-notification vibration choice. iOS decides
  /// vibration itself, so the setting is hidden there.
  bool get supportsVibrationSetting => isSupported && _isAndroid;

  /// Sets up the plugin. [onTap] receives the payload of a notification the
  /// user tapped while the app was running or in the background. [onAction]
  /// receives taps on the buttons of a reminder notification, always in a
  /// background isolate, so it must be a top-level function.
  Future<void> initialize({
    required void Function(String? payload) onTap,
    DidReceiveBackgroundNotificationResponseCallback? onAction,
  }) async {
    if (!isSupported) return;
    await refreshTimezone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_androidIcon),
        // The permission prompt is asked for explicitly, at a sensible moment,
        // never as a side effect of starting the app.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) =>
          onTap(response.payload),
      onDidReceiveBackgroundNotificationResponse: onAction,
    );
    // Push messages the system shows while the app is closed use this channel
    // (named in AndroidManifest.xml), so it must exist before the first one.
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'alerts_sv',
        'Alerts',
        description: 'Reminders and alerts from the app',
        importance: Importance.high,
      ),
    );
  }

  /// Payload of the notification that launched the app from a terminated
  /// state, if any.
  Future<String?> launchPayload() async {
    if (!isSupported) return null;
    final NotificationAppLaunchDetails? details = await _plugin
        .getNotificationAppLaunchDetails();
    return details != null && details.didNotificationLaunchApp
        ? details.notificationResponse?.payload
        : null;
  }

  /// Repeating notifications fire at a wall-clock time in the device's zone,
  /// so the zone is re-read at start and whenever the app resumes (travel,
  /// daylight-saving changes).
  Future<void> refreshTimezone() async {
    if (!isSupported) return;
    try {
      if (!_zonesLoaded) {
        tz_data.initializeTimeZones();
        _zonesLoaded = true;
      }
      final TimezoneInfo zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object catch (error) {
      // Stays on UTC. One-time notifications still fire at the right instant;
      // only repeating ones would use UTC wall-clock time.
      developer.log(
        'Could not read the device time zone: ${error.runtimeType}',
        name: 'notifications',
      );
    }
  }

  Future<bool> isPermissionGranted() async {
    if (!isSupported) return false;
    if (_isAndroid) {
      return await _android?.areNotificationsEnabled() ?? false;
    }
    final NotificationsEnabledOptions? options = await _ios?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  /// Shows the system prompt where the OS allows it. Returns whether
  /// notifications are now allowed.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    if (_isAndroid) {
      return await _android?.requestNotificationsPermission() ?? false;
    }
    return await _ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  Future<void> openSettings() async {
    if (!isSupported) return;
    await _plugin.openAppNotificationSettings();
  }

  /// Android 12+ lets users withhold exact alarms; without them reminders
  /// can arrive a few minutes late. Always true elsewhere.
  Future<bool> canScheduleExact() async {
    if (!isSupported || !_isAndroid) return true;
    return await _android?.canScheduleExactNotifications() ?? false;
  }

  Future<void> requestExactAlarms() async {
    if (!isSupported || !_isAndroid) return;
    await _android?.requestExactAlarmsPermission();
  }

  /// Makes the device's scheduled notifications exactly [planned]: entries
  /// not in the list are cancelled, the rest are (re)scheduled under their
  /// stable ids, which replaces any earlier schedule of the same reminder.
  /// Running it twice with the same input leaves the same single set.
  /// Ids in [keep] are due but possibly not delivered yet: they are left
  /// exactly as they are, neither cancelled nor rescheduled.
  ///
  /// With several accounts signed in, only scheduled notifications whose
  /// payload [owns] accepts are replaced; the others belong to other
  /// accounts and stay. [owner] tags what is scheduled (see [cancelOwned]).
  Future<void> replaceSchedule(
    List<PlannedNotification> planned, {
    required Set<int> keep,
    required bool sound,
    required bool vibration,
    String? owner,
    bool Function(String? payload)? owns,
  }) async {
    if (!isSupported) return;
    final Set<int> wanted = <int>{
      for (final PlannedNotification n in planned) n.id,
    };
    final List<PendingNotificationRequest> pending = await _plugin
        .pendingNotificationRequests();
    for (final PendingNotificationRequest request in pending) {
      if (!wanted.contains(request.id) &&
          !keep.contains(request.id) &&
          (owns == null || owns(request.payload))) {
        await _plugin.cancel(id: request.id, tag: owner);
      }
    }
    final AndroidScheduleMode mode = await canScheduleExact()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    for (final PlannedNotification n in planned) {
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime.from(n.fireAt, tz.local),
        notificationDetails: _details(
          'reminders',
          'Reminders'.tr,
          sound,
          vibration,
          tag: owner,
          actions: <AndroidNotificationAction>[
            // Handled without opening the app; tapping one also clears the
            // notification.
            for (final ReminderAction action in ReminderAction.values)
              AndroidNotificationAction(action.name, action.label.tr),
          ],
        ),
        androidScheduleMode: mode,
        title: n.title,
        body: n.body,
        payload: n.payload,
        matchDateTimeComponents: _repeatComponents(n.repeat),
      );
    }
  }

  /// Shows a notification right now (budget and recurring alerts, foreground
  /// push). A repeated call with the same [id] replaces, not stacks.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required String payload,
    required bool sound,
    required bool vibration,
    String? owner,
  }) async {
    if (!isSupported) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details(
        'alerts',
        'Alerts'.tr,
        sound,
        vibration,
        tag: owner,
      ),
      payload: payload,
    );
  }

  Future<void> cancelAll() async {
    if (!isSupported) return;
    await _plugin.cancelAll();
  }

  /// Cancels one account's notifications, scheduled and on screen, and
  /// leaves the other accounts' alone. Scheduled ones are matched by payload
  /// ([owns]); shown ones by the [owner] tag on Android, where the OS does
  /// not return payloads, and by payload elsewhere.
  Future<void> cancelOwned({
    required String owner,
    required bool Function(String? payload) owns,
  }) async {
    if (!isSupported) return;
    final List<PendingNotificationRequest> pending = await _plugin
        .pendingNotificationRequests();
    for (final PendingNotificationRequest request in pending) {
      if (owns(request.payload)) {
        await _plugin.cancel(id: request.id, tag: owner);
      }
    }
    final List<ActiveNotification> shown;
    try {
      shown = await _plugin.getActiveNotifications();
    } on Object catch (error) {
      // Older OS versions cannot list them; the shown ones then stay.
      developer.log(
        'Shown notifications could not be listed: ${error.runtimeType}',
        name: 'notifications',
      );
      return;
    }
    for (final ActiveNotification notification in shown) {
      final int? id = notification.id;
      if (id == null) continue;
      final bool mine = _isAndroid
          ? notification.tag == owner
          : owns(notification.payload);
      if (mine) await _plugin.cancel(id: id, tag: notification.tag);
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  /// Android fixes sound and vibration per channel when the channel is first
  /// created, so each on/off combination gets its own channel id. The user
  /// can still fine-tune each channel in system settings.
  ///
  /// [tag] is the account the notification belongs to, so a sign-out can
  /// remove exactly that account's shown notifications.
  NotificationDetails _details(
    String channel,
    String channelName,
    bool sound,
    bool vibration, {
    String? tag,
    List<AndroidNotificationAction>? actions,
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      '${channel}_${sound ? 's' : 'q'}${vibration ? 'v' : 'n'}',
      channelName,
      channelDescription: 'Reminders and alerts from the app'.tr,
      importance: Importance.high,
      priority: Priority.high,
      playSound: sound,
      enableVibration: vibration,
      icon: _androidIcon,
      // Hides the text on a secure lock screen.
      visibility: NotificationVisibility.private,
      tag: tag,
      actions: actions,
    ),
    iOS: DarwinNotificationDetails(presentSound: sound),
  );

  static DateTimeComponents? _repeatComponents(ReminderRepeat repeat) =>
      switch (repeat) {
        ReminderRepeat.none => null,
        ReminderRepeat.daily => DateTimeComponents.time,
        ReminderRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
        ReminderRepeat.monthly => DateTimeComponents.dayOfMonthAndTime,
        ReminderRepeat.yearly => DateTimeComponents.dateAndTime,
      };
}
