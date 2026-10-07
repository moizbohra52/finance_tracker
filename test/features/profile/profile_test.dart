import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/features/auth/views/change_password_view.dart';
import 'package:finance_tracker/features/auth/views/login_view.dart';
import 'package:finance_tracker/features/profile/views/profile_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
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
  });
  tearDown(Get.reset);

  Future<void> openProfile(WidgetTester tester) async {
    await pumpApp(tester, auth: auth, profile: profiles);
    await tapAndSettle(tester, find.byTooltip('Profile'));
    expect(find.byType(ProfileView), findsOneWidget);
  }

  testWidgets('shows the profile and saves edits', (WidgetTester tester) async {
    await openProfile(tester);
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('asha@example.com'), findsOneWidget);

    await tester.enterText(_field('Full name'), 'Asha R.');
    await tapAndSettle(tester, find.text('Save changes'));

    expect(profiles.profile.fullName, 'Asha R.');
    expect(find.text('Profile saved.'), findsOneWidget);
  });

  testWidgets('a failed load shows an error that can be retried', (
    WidgetTester tester,
  ) async {
    profiles.nextError = const NetworkFailure();
    await openProfile(tester);
    expect(find.text(const NetworkFailure().message), findsOneWidget);

    await tapAndSettle(tester, find.text('Try again'));

    expect(find.text('Asha Rao'), findsOneWidget);
  });

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
    expect(find.byType(ProfileView), findsOneWidget);
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

    await tapAndSettle(tester, dialogDelete);

    expect(auth.calls, <String>['deleteAccount', 'deleteAccount']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(LoginView), findsOneWidget);
    expect(find.text('Your account has been deleted.'), findsOneWidget);
  });

  testWidgets('cancelling the delete dialog keeps the account', (
    WidgetTester tester,
  ) async {
    await openProfile(tester);

    await tapAndSettle(tester, find.text('Delete account'));
    await tapAndSettle(tester, find.text('Cancel'));

    expect(find.byType(AlertDialog), findsNothing);
    expect(auth.calls, isEmpty);
    expect(Get.currentRoute, AppRoutes.profile);
  });
}
