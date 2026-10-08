import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// A push message reduced to what the app uses, so nothing outside this file
/// depends on Firebase types.
class PushMessage {
  const PushMessage({
    this.title,
    this.body,
    this.data = const <String, dynamic>{},
  });

  final String? title;
  final String? body;

  /// The server sends `type` and `reference_id`; see NotificationTarget.
  final Map<String, dynamic> data;
}

/// Firebase Cloud Messaging, client side only: it receives pushes and reports
/// the device token. Sending is done by a server using FCM credentials that
/// never ship in the app (docs/08_NOTIFICATION_SYSTEM.md).
///
/// Firebase needs google-services.json / GoogleService-Info.plist, which are
/// per-project secrets-adjacent files that are not committed. Without them
/// [initialize] reports unavailable and the rest of the app (local reminders
/// included) works unchanged.
///
/// Message kinds, all routed through the three streams below:
/// * foreground  - [foregroundMessages]; FCM shows nothing itself, so the
///   coordinator shows a local notification.
/// * background  - the OS shows messages that carry a `notification` block;
///   tapping one arrives on [openedMessages]. Data-only messages are not
///   supported.
/// * terminated  - tapping the notification that launched the app is read once
///   with [initialMessage].
class PushService {
  bool _available = false;

  bool get isAvailable => _available;

  bool get _platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  String get platformName =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<bool> initialize() async {
    if (!_platformSupported) return false;
    try {
      await Firebase.initializeApp();
      _available = true;
    } on Object catch (error) {
      developer.log(
        'Push messaging is off, Firebase is not configured: '
        '${error.runtimeType}',
        name: 'notifications',
      );
    }
    return _available;
  }

  Future<String?> token() async {
    if (!_available) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } on Object catch (error) {
      // Never log the token or the error text, only that it failed.
      developer.log(
        'Could not get a push token: ${error.runtimeType}',
        name: 'notifications',
      );
      return null;
    }
  }

  Stream<String> get tokenRefreshes => _available
      ? FirebaseMessaging.instance.onTokenRefresh
      : const Stream<String>.empty();

  Stream<PushMessage> get foregroundMessages => _available
      ? FirebaseMessaging.onMessage.map(_convert)
      : const Stream<PushMessage>.empty();

  Stream<PushMessage> get openedMessages => _available
      ? FirebaseMessaging.onMessageOpenedApp.map(_convert)
      : const Stream<PushMessage>.empty();

  Future<PushMessage?> initialMessage() async {
    if (!_available) return null;
    final RemoteMessage? message = await FirebaseMessaging.instance
        .getInitialMessage();
    return message == null ? null : _convert(message);
  }

  Future<void> deleteToken() async {
    if (!_available) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } on Object catch (error) {
      developer.log(
        'Could not delete the push token: ${error.runtimeType}',
        name: 'notifications',
      );
    }
  }

  static PushMessage _convert(RemoteMessage message) => PushMessage(
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
  );
}
