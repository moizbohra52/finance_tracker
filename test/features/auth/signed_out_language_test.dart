import 'package:finance_tracker/core/services/device_auth_service.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/app_lock/controllers/app_lock_controller.dart';
import 'package:finance_tracker/features/auth/views/login_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fakes.dart';

String _hi(String english) => hindi[english]!;

Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// Storage as a restart finds it: whatever an earlier run saved.
Future<StorageService> _storage([Map<String, Object> saved = const {}]) async {
  SharedPreferences.setMockInitialValues(saved);
  return StorageService(await SharedPreferences.getInstance());
}

Future<void> _chooseHindi(WidgetTester tester) async {
  await tapAndSettle(tester, find.byTooltip('Language'.tr));
  await tapAndSettle(tester, find.text(AppLanguage.hindi.label));
}

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository());
  tearDown(() {
    Get.reset();
    Get.locale = AppLanguage.english.locale;
  });

  testWidgets('the app opens in the language this device used last', (
    WidgetTester tester,
  ) async {
    final StorageService storage = await _storage(<String, Object>{
      'app.language': AppLanguage.hindi.stored,
    });
    await pumpApp(tester, auth: auth, storage: storage);

    expect(find.text(_hi('Get started')), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('the language chosen on onboarding carries to sign-in', (
    WidgetTester tester,
  ) async {
    final StorageService storage = await _storage();
    await pumpApp(tester, auth: auth, storage: storage);

    await _chooseHindi(tester);
    expect(find.text(_hi('Get started')), findsOneWidget);

    await tapAndSettle(tester, find.text(_hi('I already have an account')));
    expect(find.byType(LoginView), findsOneWidget);
    expect(find.text(_hi('Welcome back')), findsOneWidget);
    expect(storage.readLanguage(), AppLanguage.hindi.stored);
  });

  testWidgets('a new account starts in the language chosen at sign-in', (
    WidgetTester tester,
  ) async {
    auth.signUpStartsSession = false;
    await pumpApp(tester, auth: auth, storage: await _storage());
    await tapAndSettle(tester, find.text('I already have an account'));
    await _chooseHindi(tester);
    expect(find.text(_hi('Sign in to see your balances.')), findsOneWidget);

    await tapAndSettle(tester, find.text(_hi('Create one')));
    await tester.enterText(_field(_hi('Full name')), 'Asha Verma');
    await tester.enterText(_field(_hi('Email')), 'asha@example.com');
    await tester.enterText(_field(_hi('Password')), 'secret123');
    await tester.enterText(_field(_hi('Confirm password')), 'secret123');
    await tapAndSettle(tester, find.text(_hi('Create account')));

    expect(auth.calls, contains('signUp'));
    expect(auth.signUpLanguage, AppLanguage.hindi.stored);
    expect(find.text(_hi('Check your email')), findsOneWidget);
  });

  testWidgets('a Hindi account sees the lock screen in Hindi', (
    WidgetTester tester,
  ) async {
    final StorageService storage = await _storage(<String, Object>{
      'security.app_lock': true,
      'app.language': AppLanguage.hindi.stored,
    });
    final FakeAuthRepository signedIn = FakeAuthRepository(signedIn: true);
    final FakeDeviceAuth device = FakeDeviceAuth()
      ..next = DeviceAuthResult.cancelled;
    final FakeUserSettingsRepository settings = FakeUserSettingsRepository()
      ..settings = UserSettings(
        dateFormat: 'd MMM y',
        numberFormat: 'indian',
        firstDayOfWeek: 'monday',
        languageCode: AppLanguage.hindi.stored,
        defaultAccountId: null,
      );
    await pumpApp(
      tester,
      auth: signedIn,
      storage: storage,
      userSettings: settings,
      appLock: AppLockController(
        deviceAuth: device,
        storage: storage,
        auth: signedIn,
      ),
    );

    expect(
      find.text(_hi('Unlock with your fingerprint, face or screen lock.')),
      findsOneWidget,
    );
    expect(find.text(_hi('Tap Unlock to try again.')), findsOneWidget);
    expect(
      device.prompts.first,
      _hi('Unlock @app').replaceAll('@app', 'Track Day'),
    );
  });
}
