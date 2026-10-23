import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/data/datasources/local/saved_login_store.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:finance_tracker/domain/entities/saved_login.dart';
import 'package:finance_tracker/features/auth/controllers/account_switch_controller.dart';
import 'package:finance_tracker/features/auth/views/add_account_view.dart';
import 'package:finance_tracker/features/auth/views/login_view.dart';
import 'package:finance_tracker/features/dashboard/views/app_shell_view.dart';
import 'package:finance_tracker/features/profile/widgets/profile_avatar.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fake_notifications.dart';
import '../../helpers/fakes.dart';

const String _reminderId = 'a1b2c3d4-0000-4000-8000-0000000000a1';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// The app signed in as user-1 (Asha), optionally with Ravi (user-2) already
/// signed in on the device too.
Future<NotificationsHandle> _start(
  WidgetTester tester,
  FakeAuthRepository auth, {
  bool withRavi = true,
  String? launch,
  FakeUserSettingsRepository? userSettings,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  if (withRavi) {
    await SavedLoginStore(preferences).save(
      SavedLogin(
        userId: 'user-2',
        email: 'ravi@example.com',
        displayName: 'Ravi Kumar',
        lastUsedAt: DateTime(2026),
      ),
      session: FakeAuthRepository.sessionOf('user-2', 'ravi@example.com'),
    );
  }
  final StorageService storage = StorageService(preferences);
  final FakeFinance finance = FakeFinance();
  final NotificationsHandle handle = await buildCoordinator(
    finance,
    auth: auth,
    storage: storage,
    local: FakeLocalNotifications(granted: true)..launch = launch,
  );
  await pumpApp(
    tester,
    auth: auth,
    finance: finance,
    notifications: handle,
    storage: storage,
    userSettings: userSettings,
  );
  return handle;
}

Future<void> _openSwitcher(WidgetTester tester) async {
  await tester.longPress(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(ProfileAvatar),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Switch account'), findsOneWidget);
}

List<String> _savedIds() => Get.find<AccountSwitchController>().logins
    .map((SavedLogin login) => login.userId)
    .toList();

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository(signedIn: true));
  tearDown(Get.reset);

  testWidgets('the switcher lists every signed-in account', (
    WidgetTester tester,
  ) async {
    await _start(tester, auth);
    await _openSwitcher(tester);

    expect(find.text('asha@example.com'), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('Sign in to another account'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('switching shows the other account and keeps both signed in', (
    WidgetTester tester,
  ) async {
    await _start(tester, auth);
    await _openSwitcher(tester);

    await tester.tap(find.text('Ravi Kumar'));
    await tester.pumpAndSettle();

    expect(auth.currentUserId, 'user-2');
    expect(find.byType(AppShellView), findsOneWidget);
    expect(auth.heldSessions, 1, reason: 'the first session was kept');
    expect(_savedIds(), <String>['user-2', 'user-1']);

    // And back again.
    await _openSwitcher(tester);
    await tester.tap(find.text('asha@example.com'));
    await tester.pumpAndSettle();
    expect(auth.currentUserId, 'user-1');
    expect(_savedIds(), <String>['user-1', 'user-2']);
  });

  testWidgets('a Hindi account keeps Hindi on the switching screen', (
    WidgetTester tester,
  ) async {
    final FakeUserSettingsRepository settings = FakeUserSettingsRepository()
      ..settings = const UserSettings(
        dateFormat: 'd MMM y',
        numberFormat: 'indian',
        firstDayOfWeek: 'monday',
        languageCode: 'hi',
        defaultAccountId: null,
      );
    await _start(tester, auth, userSettings: settings);
    await tester.longPress(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(ProfileAvatar),
      ),
    );
    await tester.pumpAndSettle();

    // The next account's settings take a moment to load, as on a phone.
    settings.fetchDelay = const Duration(milliseconds: 500);
    await tester.tap(find.text('Ravi Kumar'));
    final String inHindi = hindi['Switching to @name']!.replaceAll(
      '@name',
      'Ravi Kumar',
    );
    bool sawHindi = false;
    bool sawEnglish = false;
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      sawHindi |= find.text(inHindi).evaluate().isNotEmpty;
      // English text on the switching screen, or the next account's screens
      // shown in English until its settings arrive.
      sawEnglish |=
          Get.locale?.languageCode == 'en' ||
          find.text('Switching to Ravi Kumar').evaluate().isNotEmpty ||
          find.text('Home').evaluate().isNotEmpty;
    }
    await tester.pumpAndSettle();

    expect(auth.currentUserId, 'user-2');
    expect(sawHindi, isTrue);
    expect(sawEnglish, isFalse, reason: 'the language must not drop mid-switch');
  });

  testWidgets('adding an account signs in to it and switches', (
    WidgetTester tester,
  ) async {
    auth.otherAccounts['meera@example.com'] = (
      userId: 'user-3',
      password: 'secret-pass1',
      name: 'Meera',
    );
    await _start(tester, auth, withRavi: false);
    await _openSwitcher(tester);
    await tester.tap(find.text('Sign in to another account'));
    await tester.pumpAndSettle();
    expect(find.byType(AddAccountView), findsOneWidget);

    await tester.enterText(_field('Email'), 'meera@example.com');
    await tester.enterText(_field('Password'), 'wrong-pass1');
    await tapAndSettle(tester, find.text('Sign in and switch'));
    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(auth.currentUserId, 'user-1', reason: 'nothing changed');

    await tester.enterText(_field('Password'), 'secret-pass1');
    await tapAndSettle(tester, find.text('Sign in and switch'));

    expect(auth.currentUserId, 'user-3');
    expect(find.byType(AppShellView), findsOneWidget);
    expect(_savedIds(), <String>['user-3', 'user-1']);
  });

  testWidgets('signing out hands over to the other signed-in account', (
    WidgetTester tester,
  ) async {
    await _start(tester, auth);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You will switch to Ravi Kumar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(auth.currentUserId, 'user-2');
    expect(find.byType(AppShellView), findsOneWidget);
    expect(find.byType(LoginView), findsNothing);
    expect(_savedIds(), <String>['user-2']);
  });

  testWidgets('signing out of the last account shows sign-in', (
    WidgetTester tester,
  ) async {
    await _start(tester, auth, withRavi: false);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginView), findsOneWidget);
    expect(_savedIds(), isEmpty);
  });

  testWidgets('an account whose session ended is removed, not switched to', (
    WidgetTester tester,
  ) async {
    auth.revoked.add('user-2');
    await _start(tester, auth);
    await _openSwitcher(tester);

    await tester.tap(find.text('Ravi Kumar'));
    await tester.pumpAndSettle();

    expect(auth.currentUserId, 'user-1');
    expect(find.byType(AppShellView), findsOneWidget);
    expect(find.textContaining('signed out of ravi@example.com'), findsOneWidget);
    expect(_savedIds(), <String>['user-1']);
  });

  group('notifications', () {
    testWidgets('a tap for another signed-in account switches and opens it', (
      WidgetTester tester,
    ) async {
      final NotificationsHandle h = await _start(tester, auth);

      h.local.tap('user-2|reminder:$_reminderId');
      await tester.pumpAndSettle();

      expect(auth.currentUserId, 'user-2');
      expect(Get.currentRoute, AppRoutes.reminderDetail);
      expect(Get.arguments, _reminderId);
      expect(find.text('Switched to Ravi Kumar'), findsOneWidget);
    });

    testWidgets('a cold start from another account opens in that account', (
      WidgetTester tester,
    ) async {
      await _start(tester, auth, launch: 'user-2|reminder:$_reminderId');

      expect(auth.currentUserId, 'user-2');
      expect(Get.currentRoute, AppRoutes.reminderDetail);
    });

    testWidgets('a tap for the active account opens without a switch', (
      WidgetTester tester,
    ) async {
      final NotificationsHandle h = await _start(tester, auth);

      h.local.tap('user-1|reminder:$_reminderId');
      await tester.pumpAndSettle();

      expect(auth.currentUserId, 'user-1');
      expect(auth.heldSessions, 0);
      expect(Get.currentRoute, AppRoutes.reminderDetail);
    });

    testWidgets('a tap for an account not signed in here stays put', (
      WidgetTester tester,
    ) async {
      final NotificationsHandle h = await _start(tester, auth);

      h.local.tap('user-9|reminder:$_reminderId');
      await tester.pumpAndSettle();

      expect(auth.currentUserId, 'user-1');
      expect(find.byType(AppShellView), findsOneWidget);
      expect(
        find.textContaining('not signed in on this device'),
        findsOneWidget,
      );
    });
  });
}
