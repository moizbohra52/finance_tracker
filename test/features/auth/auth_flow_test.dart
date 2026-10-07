import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:finance_tracker/features/auth/views/forgot_password_view.dart';
import 'package:finance_tracker/features/auth/views/login_view.dart';
import 'package:finance_tracker/features/auth/views/onboarding_view.dart';
import 'package:finance_tracker/features/auth/views/reset_password_view.dart';
import 'package:finance_tracker/features/dashboard/views/dashboard_view.dart';
import 'package:finance_tracker/features/profile/views/profile_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fakes.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _openLogin(WidgetTester tester) async {
  await tapAndSettle(tester, find.text('I already have an account'));
  expect(find.byType(LoginView), findsOneWidget);
}

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository());
  tearDown(Get.reset);

  group('startup and guards', () {
    testWidgets('signed-out start shows onboarding', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: auth);

      expect(find.byType(OnboardingView), findsOneWidget);
    });

    testWidgets('a restored session starts on the dashboard', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));

      expect(find.byType(DashboardView), findsOneWidget);
    });

    testWidgets('protected routes send signed-out users to sign in', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: auth);

      Get.toNamed<void>(AppRoutes.profile)?.ignore();
      await tester.pumpAndSettle();

      expect(find.byType(ProfileView), findsNothing);
      expect(find.byType(LoginView), findsOneWidget);
    });

    testWidgets('signed-in users cannot open guest screens', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));

      Get.toNamed<void>(AppRoutes.login)?.ignore();
      await tester.pumpAndSettle();

      expect(find.byType(LoginView), findsNothing);
      expect(find.byType(DashboardView), findsOneWidget);
    });

    test(
      'a recovery link that arrives before the splash routes is kept',
      () async {
        final AuthController controller = Get.put(AuthController(auth));

        auth.emit(AuthStatus.passwordRecovery);
        await Future<void>.delayed(Duration.zero);

        expect(controller.takeStartRoute(), AppRoutes.resetPassword);
      },
    );
  });

  group('login', () {
    testWidgets('validates before calling the server', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: auth);
      await _openLogin(tester);

      await tapAndSettle(tester, find.text('Sign in'));

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('shows the server error and stays on the form', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: auth);
      await _openLogin(tester);
      await tester.enterText(_field('Email'), 'asha@example.com');
      await tester.enterText(_field('Password'), 'wrong-pass1');
      auth.nextError = const AuthFailure('Incorrect email or password.');

      await tapAndSettle(tester, find.text('Sign in'));

      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.byType(LoginView), findsOneWidget);
    });

    testWidgets('success opens the dashboard', (WidgetTester tester) async {
      await pumpApp(tester, auth: auth);
      await _openLogin(tester);
      await tester.enterText(_field('Email'), 'asha@example.com');
      await tester.enterText(_field('Password'), 'secret123');

      await tapAndSettle(tester, find.text('Sign in'));

      expect(auth.calls, <String>['signIn']);
      expect(find.byType(DashboardView), findsOneWidget);
    });
  });

  group('register', () {
    Future<void> fillForm(
      WidgetTester tester, {
      String password = 'secret123',
    }) async {
      await tapAndSettle(tester, find.text('Get started'));
      await tester.enterText(_field('Full name'), 'Asha Rao');
      await tester.enterText(_field('Email'), 'asha@example.com');
      await tester.enterText(_field('Password'), password);
      await tester.enterText(_field('Confirm password'), 'secret123');
    }

    testWidgets('enforces the password policy and confirmation', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: auth);
      await fillForm(tester, password: 'short');

      await tapAndSettle(tester, find.text('Create account'));

      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('asks the user to confirm their email when required', (
      WidgetTester tester,
    ) async {
      auth.signUpStartsSession = false;
      await pumpApp(tester, auth: auth);
      await fillForm(tester);

      await tapAndSettle(tester, find.text('Create account'));

      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('asha@example.com'), findsOneWidget);
    });

    testWidgets('opens the dashboard when no confirmation is needed', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: auth);
      await fillForm(tester);

      await tapAndSettle(tester, find.text('Create account'));

      expect(find.byType(DashboardView), findsOneWidget);
    });
  });

  group('password reset', () {
    testWidgets('forgot password confirms the link was sent', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: auth);
      await _openLogin(tester);
      await tapAndSettle(tester, find.text('Forgot password?'));
      expect(find.byType(ForgotPasswordView), findsOneWidget);

      await tester.enterText(_field('Email'), 'asha@example.com');
      await tapAndSettle(tester, find.text('Send reset link'));

      expect(auth.calls, <String>['sendPasswordReset']);
      expect(find.textContaining('a reset link is on its way'), findsOneWidget);
    });

    testWidgets('a recovery link opens the reset screen and saves', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, auth: auth);

      auth.emit(AuthStatus.passwordRecovery);
      await tester.pumpAndSettle();
      expect(find.byType(ResetPasswordView), findsOneWidget);

      await tester.enterText(_field('New password'), 'newpass123');
      await tester.enterText(_field('Confirm new password'), 'newpass123');
      await tapAndSettle(tester, find.text('Save password'));

      expect(auth.calls, <String>['updatePassword']);
      expect(find.byType(DashboardView), findsOneWidget);
      expect(find.text('Your password has been updated.'), findsOneWidget);
    });
  });

  testWidgets('a sign-out event from anywhere returns to sign in', (
    WidgetTester tester,
  ) async {
    auth = FakeAuthRepository(signedIn: true);
    await pumpApp(tester, auth: auth);

    auth.emit(AuthStatus.signedOut);
    await tester.pumpAndSettle();

    expect(find.byType(LoginView), findsOneWidget);
  });
}
