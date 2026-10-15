import 'dart:async';

import 'package:finance_tracker/core/services/device_auth_service.dart';
import 'package:finance_tracker/core/services/external_activity.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/features/app_lock/controllers/app_lock_controller.dart';
import 'package:finance_tracker/features/auth/views/onboarding_view.dart';
import 'package:finance_tracker/features/dashboard/views/app_shell_view.dart';
import 'package:finance_tracker/features/settings/views/settings_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_notifications.dart';
import '../../helpers/fakes.dart';

const String _lockedTitle = 'Track Day is locked';
const String _reminderId = 'a1b2c3d4-0000-4000-8000-0000000000a1';

Finder _lockSwitch() => find.widgetWithText(SwitchListTile, 'App lock');

void main() {
  late FakeAuthRepository auth;
  late FakeDeviceAuth device;
  late DateTime now;

  setUp(() {
    auth = FakeAuthRepository(signedIn: true);
    device = FakeDeviceAuth();
    now = DateTime(2026, 10, 15, 10);
  });
  tearDown(Get.reset);

  /// The app with app lock already on (or off), as after a restart.
  Future<AppLockController> start(
    WidgetTester tester, {
    bool lockOn = true,
    FakeLocalNotifications? local,
  }) async {
    // A fresh tree, as at a real start: the lock's back-button observer must
    // come before the navigator's, which an app kept from the previous test
    // would not allow.
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues(<String, Object>{
      'security.app_lock': lockOn,
    });
    final StorageService storage = StorageService(
      await SharedPreferences.getInstance(),
    );
    final AppLockController lock = AppLockController(
      deviceAuth: device,
      storage: storage,
      auth: auth,
      clock: () => now,
    );
    await pumpApp(
      tester,
      auth: auth,
      storage: storage,
      appLock: lock,
      localNotifications: local,
    );
    return lock;
  }

  // The platform steps through every state in between; so do these.
  Future<void> background(WidgetTester tester) async {
    for (final AppLifecycleState state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final AppLifecycleState state in <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    unawaited(Get.toNamed<void>(AppRoutes.settings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);
  }

  group('turning it on and off', () {
    testWidgets('turning it on asks for the fingerprint or face first', (
      WidgetTester tester,
    ) async {
      final AppLockController lock = await start(tester, lockOn: false);
      await openSettings(tester);

      await tapAndSettle(tester, _lockSwitch());

      expect(device.prompts, <String>['Confirm to turn on app lock']);
      expect(lock.enabled.value, isTrue);
      expect(lock.locked.value, isFalse, reason: 'the user just proved it');
      expect(
        (await SharedPreferences.getInstance()).getBool('security.app_lock'),
        isTrue,
      );
    });

    testWidgets('a cancelled check leaves it off', (WidgetTester tester) async {
      final AppLockController lock = await start(tester, lockOn: false);
      await openSettings(tester);
      device.next = DeviceAuthResult.cancelled;

      await tapAndSettle(tester, _lockSwitch());

      expect(lock.enabled.value, isFalse);
      expect(tester.widget<SwitchListTile>(_lockSwitch()).value, isFalse);
    });

    testWidgets('a phone without any screen lock cannot turn it on', (
      WidgetTester tester,
    ) async {
      device.available = false;
      final AppLockController lock = await start(tester, lockOn: false);
      await openSettings(tester);

      await tapAndSettle(tester, _lockSwitch());

      expect(lock.enabled.value, isFalse);
      expect(device.prompts, isEmpty);
      expect(
        find.textContaining('Set up a fingerprint, face, PIN or pattern'),
        findsOneWidget,
      );
    });

    testWidgets('turning it off asks too', (WidgetTester tester) async {
      final AppLockController lock = await start(tester);
      await openSettings(tester);
      device.prompts.clear();

      await tapAndSettle(tester, _lockSwitch());

      expect(device.prompts, <String>['Confirm to turn off app lock']);
      expect(lock.enabled.value, isFalse);
    });

    testWidgets('not offered where the platform has no such check', (
      WidgetTester tester,
    ) async {
      device.supported = false;
      await start(tester, lockOn: false);
      await openSettings(tester);
      expect(_lockSwitch(), findsNothing);
    });
  });

  group('locked app', () {
    testWidgets('a start asks right away and opens on success', (
      WidgetTester tester,
    ) async {
      await start(tester);

      expect(device.prompts, <String>['Unlock Track Day']);
      expect(find.text(_lockedTitle), findsNothing);
      expect(find.byType(AppShellView), findsOneWidget);
    });

    testWidgets('a cancelled check keeps the app covered until it passes', (
      WidgetTester tester,
    ) async {
      device.next = DeviceAuthResult.cancelled;
      await start(tester);
      expect(find.text(_lockedTitle), findsOneWidget);

      device.next = DeviceAuthResult.success;
      await tapAndSettle(tester, find.text('Unlock'));

      expect(find.text(_lockedTitle), findsNothing);
      expect(find.byType(AppShellView), findsOneWidget);
    });

    testWidgets('every return from the background asks again', (
      WidgetTester tester,
    ) async {
      final AppLockController lock = await start(tester);
      device.prompts.clear();

      await background(tester);
      expect(lock.locked.value, isTrue);

      await foreground(tester);
      expect(device.prompts, hasLength(1));
      expect(lock.locked.value, isFalse);
    });

    testWidgets('too many attempts say so on the lock screen', (
      WidgetTester tester,
    ) async {
      device.next = DeviceAuthResult.lockedOut;
      await start(tester);
      expect(find.textContaining('Too many attempts'), findsOneWidget);
      expect(find.text(_lockedTitle), findsOneWidget);
    });

    testWidgets('a phone whose screen lock was removed turns the lock off', (
      WidgetTester tester,
    ) async {
      device.next = DeviceAuthResult.unavailable;
      final AppLockController lock = await start(tester);

      expect(lock.enabled.value, isFalse);
      expect(find.text(_lockedTitle), findsNothing);
      expect(find.textContaining('no longer has a screen lock'), findsOneWidget);
    });

    testWidgets('signed out, there is nothing to lock', (
      WidgetTester tester,
    ) async {
      auth = FakeAuthRepository();
      await start(tester);
      expect(find.text(_lockedTitle), findsNothing);
      expect(find.byType(OnboardingView), findsOneWidget);
      expect(device.prompts, isEmpty);
    });

    testWidgets('back on the lock screen leaves the app, not the screen', (
      WidgetTester tester,
    ) async {
      final List<String> platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await start(tester);
      await openSettings(tester);
      await background(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(platformCalls, contains('SystemNavigator.pop'));
      expect(Get.currentRoute, AppRoutes.settings, reason: 'not popped');
      // Lifecycle listeners outlive a test; leave them in the foreground.
      await foreground(tester);
    });

    testWidgets('a notification tapped while locked opens underneath', (
      WidgetTester tester,
    ) async {
      device.next = DeviceAuthResult.cancelled;
      final FakeLocalNotifications local = FakeLocalNotifications(
        granted: true,
      );
      await start(tester, local: local);

      local.tap('user-1|reminder:$_reminderId');
      await tester.pumpAndSettle();

      expect(Get.currentRoute, AppRoutes.reminderDetail);
      expect(find.text(_lockedTitle), findsOneWidget, reason: 'still hidden');
    });
  });

  group('screens the app opens itself', () {
    testWidgets('a quick return from the photo picker does not ask', (
      WidgetTester tester,
    ) async {
      final AppLockController lock = await start(tester);
      device.prompts.clear();
      final Completer<void> picker = Completer<void>();
      unawaited(ExternalActivity.run(() => picker.future));

      await background(tester);
      now = now.add(const Duration(seconds: 30));
      await foreground(tester);
      picker.complete();

      expect(lock.locked.value, isFalse);
      expect(device.prompts, isEmpty);
    });

    testWidgets('staying away longer than the grace asks again', (
      WidgetTester tester,
    ) async {
      final AppLockController lock = await start(tester);
      device.prompts.clear();
      device.next = DeviceAuthResult.cancelled;
      final Completer<void> share = Completer<void>();
      unawaited(ExternalActivity.run(() => share.future));

      await background(tester);
      now = now.add(AppLockController.externalGrace);
      await foreground(tester);
      share.complete();

      expect(lock.locked.value, isTrue);
      expect(device.prompts, hasLength(1));
    });
  });
}
