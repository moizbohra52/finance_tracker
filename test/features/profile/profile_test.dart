import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/auth/views/change_password_view.dart';
import 'package:finance_tracker/features/auth/views/login_view.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/profile/views/profile_view.dart';
import 'package:finance_tracker/features/profile/widgets/profile_avatar.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fakes.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;

  setUp(() {
    auth = FakeAuthRepository(signedIn: true);
    profiles = FakeProfileRepository();
    // The device time zone comes from a platform channel that tests do not
    // have; answer it the way a device in India would.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (MethodCall call) async => 'Asia/Kolkata',
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
    AppFormatters.preferences = UserPreferences.defaults;
    Get.reset();
  });

  Future<void> openProfile(WidgetTester tester) async {
    await pumpApp(tester, auth: auth, profile: profiles);
    // Tap the profile tab in the bottom navigation
    await tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.person_outline),
      ),
    );
    expect(find.byType(ProfileContent), findsOneWidget);
  }

  testWidgets('shows the profile and saves edits', (WidgetTester tester) async {
    await openProfile(tester);
    expect(find.text('Asha Rao'), findsWidgets);
    expect(find.text('asha@example.com'), findsWidgets);
    expect(find.text('Asia/Kolkata'), findsOneWidget);

    await tester.enterText(_field('Full name'), 'Asha R.');
    await tapAndSettle(tester, find.text('Save changes'));

    expect(profiles.profile.fullName, 'Asha R.');
    expect(find.text('Profile saved.'), findsOneWidget);
  });

  testWidgets('an invalid name shows the reason and saves nothing', (
    WidgetTester tester,
  ) async {
    await openProfile(tester);

    await tester.enterText(_field('Full name'), 'Asha 2');
    await tapAndSettle(tester, find.text('Save changes'));

    expect(
      find.text('Use letters, spaces, dots, apostrophes or hyphens only'),
      findsOneWidget,
    );
    expect(profiles.profile.fullName, 'Asha Rao');
  });

  testWidgets('an invalid mobile number shows the reason and saves nothing', (
    WidgetTester tester,
  ) async {
    await openProfile(tester);

    await tester.enterText(_field('Mobile (optional)'), 'call me');
    await tapAndSettle(tester, find.text('Save changes'));

    expect(find.text('Enter a valid mobile number'), findsOneWidget);
    expect(profiles.profile.mobile, '+91 98765 43210');
  });

  testWidgets('a failed load shows an error that can be retried', (
    WidgetTester tester,
  ) async {
    await openProfile(tester);
    // The profile tab already has its data; a reload is what fails here.
    profiles.nextError = const NetworkFailure();
    await Get.find<ProfileController>().loadProfile();
    await tester.pumpAndSettle();
    expect(find.text(const NetworkFailure().message), findsOneWidget);

    await tapAndSettle(tester, find.text('Try again'));

    expect(find.text('Asha Rao'), findsWidgets);
  });

  testWidgets(
    'a profile photo that cannot load shows the fallback, not an error',
    (WidgetTester tester) async {
      profiles.profile = const Profile(
        id: 'user-1',
        fullName: 'Asha Rao',
        mobile: '+91 98765 43210',
        avatarPath: 'user-1/0.jpg',
        currencyCode: 'INR',
        timezone: 'Asia/Kolkata',
      );
      await openProfile(tester);

      expect(find.byType(ProfileAvatar), findsOneWidget);
      // The test network refuses the image; the widget must absorb that.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('change password is reachable from the profile', (
    WidgetTester tester,
  ) async {
    await openProfile(tester);

    await tapAndSettle(tester, find.text('Change password'));
    expect(find.byType(ChangePasswordView), findsOneWidget);
    await tester.enterText(_field('Current password'), 'secret123');
    await tester.enterText(_field('New password'), 'newpass123');
    await tester.enterText(_field('Confirm new password'), 'newpass123');
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, 'Change password'),
    );

    expect(auth.calls, <String>['changePassword']);
    expect(find.byType(ProfileContent), findsOneWidget);
    expect(find.text('Your password has been changed.'), findsOneWidget);
  });

  testWidgets('sign out returns to sign in', (WidgetTester tester) async {
    await openProfile(tester);

    await tapAndSettle(tester, find.text('Sign out'));

    expect(auth.calls, <String>['signOut']);
    expect(find.byType(LoginView), findsOneWidget);
  });

  testWidgets('delete account needs confirmation and the password', (
    WidgetTester tester,
  ) async {
    await openProfile(tester);
    final Finder dialogDelete = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Delete account'),
    );

    await tapAndSettle(tester, find.text('Delete account'));
    expect(find.text('Delete your account?'), findsOneWidget);

    await tapAndSettle(tester, dialogDelete);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(auth.calls, isEmpty);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: _field('Password'),
      ),
      'wrong-pass1',
    );
    auth.nextError = const AuthFailure('Your password is incorrect.');
    await tapAndSettle(tester, dialogDelete);
    expect(find.text('Your password is incorrect.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(auth.isSignedIn, isTrue, reason: 'a wrong password logs nobody out');

    await tapAndSettle(tester, dialogDelete);

    expect(auth.calls, <String>['deleteAccount', 'deleteAccount']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(LoginView), findsOneWidget);
    expect(find.text('Your account has been deleted.'), findsOneWidget);
  });

  testWidgets('a failed deletion keeps the user signed in', (
    WidgetTester tester,
  ) async {
    await openProfile(tester);

    await tapAndSettle(tester, find.text('Delete account'));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: _field('Password'),
      ),
      'right-pass1',
    );
    auth.nextError = const NetworkFailure();
    await tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete account'),
      ),
    );

    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(auth.isSignedIn, isTrue);
    expect(find.byType(LoginView), findsNothing);
  });

  testWidgets('cancelling the delete dialog keeps the account', (
    WidgetTester tester,
  ) async {
    await openProfile(tester);

    await tapAndSettle(tester, find.text('Delete account'));
    await tapAndSettle(tester, find.text('Cancel'));

    expect(find.byType(AlertDialog), findsNothing);
    expect(auth.calls, isEmpty);
    expect(Get.currentRoute, AppRoutes.dashboard);
  });
}
