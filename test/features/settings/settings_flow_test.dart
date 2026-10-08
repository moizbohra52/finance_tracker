import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/auth/views/login_view.dart';
import 'package:finance_tracker/features/budgets/controllers/budget_controller.dart';
import 'package:finance_tracker/features/dashboard/controllers/home_controller.dart';
import 'package:finance_tracker/features/dashboard/views/app_shell_view.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:finance_tracker/features/settings/views/information_views.dart';
import 'package:finance_tracker/features/settings/views/settings_view.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/views/transaction_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

/// Everything the app keeps on the server and on the device, passed to each
/// launch so a restart sees what the previous one saved.
class _Account {
  _Account()
    : finance = FakeFinance()
        ..addAccount('Cash', '1000')
        ..addAccount('Bank', '500', id: 'acc-2');

  final FakeFinance finance;
  final FakeAuthRepository auth = FakeAuthRepository(signedIn: true);
  final FakeProfileRepository profiles = FakeProfileRepository();
  final FakeUserSettingsRepository userSettings = FakeUserSettingsRepository();
  late StorageService storage;

  /// Starts the app as a fresh launch. The previous app is taken down first,
  /// so its routes and controllers are not still in use when GetX resets.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    await pumpApp(
      tester,
      auth: auth,
      profile: profiles,
      userSettings: userSettings,
      finance: finance,
      storage: storage,
    );
  }
}

Future<void> _openSettings(WidgetTester tester) async {
  unawaited(Get.toNamed<void>(AppRoutes.settings));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsView), findsOneWidget);
}

/// Picks [option] from the bottom sheet opened by the row [row].
Future<void> _choose(WidgetTester tester, String row, String option) async {
  await tapAndSettle(tester, find.text(row));
  await tapAndSettle(tester, find.text(option));
}

void main() {
  // Snack bars and the bottom-sheet route need the widget binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Account account;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    account = _Account()
      ..storage = StorageService(await SharedPreferences.getInstance());
  });

  tearDown(() {
    AppFormatters.preferences = UserPreferences.defaults;
    Get.reset();
  });

  group('theme', () {
    testWidgets('a theme change applies at once and survives a restart', (
      WidgetTester tester,
    ) async {
      await account.launch(tester);
      await _openSettings(tester);

      await tapAndSettle(tester, find.text('Dark'));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      await account.launch(tester);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
        reason: 'the saved theme is read on the next launch',
      );
    });

    testWidgets('the logo colours are offered first, under their own heading', (
      WidgetTester tester,
    ) async {
      await account.launch(tester);
      await _openSettings(tester);

      expect(find.text('Logo colours'), findsOneWidget);
      expect(find.text('More colours'), findsOneWidget);
      for (final String name in <String>['Ember', 'Sun', 'Cocoa', 'Sand']) {
        expect(find.text(name), findsOneWidget);
      }
      // The logo row sits above the other colours.
      expect(
        tester.getTopLeft(find.text('Ember')).dy,
        lessThan(tester.getTopLeft(find.text('Indigo')).dy),
      );
    });

    testWidgets('a logo colour recolours the app and is remembered', (
      WidgetTester tester,
    ) async {
      final Color expected = AppTheme.lightFor(
        AppColors.logoEmber,
        variant: DynamicSchemeVariant.fidelity,
      ).colorScheme.primary;

      await account.launch(tester);
      await _openSettings(tester);
      await tapAndSettle(tester, find.text('Ember'));

      expect(
        Theme.of(tester.element(find.byType(SettingsView))).colorScheme.primary,
        expected,
        reason: 'the theme changes at once',
      );
      expect(account.storage.readAccentColor(), 'ember');

      await account.launch(tester);
      expect(
        Theme.of(tester.element(find.byType(AppShellView))).colorScheme.primary,
        expected,
        reason: 'the choice is read on the next launch',
      );
    });

    testWidgets('the accent colour is saved too', (WidgetTester tester) async {
      await account.launch(tester);
      await _openSettings(tester);

      await tapAndSettle(tester, find.text('Rose'));
      expect(account.storage.readAccentColor(), 'rose');
    });
  });

  group('currency', () {
    testWidgets('is saved to the account, shown, and used after a restart', (
      WidgetTester tester,
    ) async {
      await account.launch(tester);
      await _openSettings(tester);

      await _choose(tester, 'Currency', 'US dollar (USD)');

      expect(account.profiles.profile.currencyCode, 'USD');
      expect(find.text('Settings saved.'), findsOneWidget);
      expect(find.textContaining('USD'), findsWidgets);

      await account.launch(tester);
      expect(AppFormatters.preferences.currencyCode, 'USD');
      expect(AppFormatters.money(Decimal.parse('1000')), isNot(contains('₹')));
    });

    testWidgets('a currency the server rejects is not shown as saved', (
      WidgetTester tester,
    ) async {
      await account.launch(tester);
      await _openSettings(tester);
      account.profiles.nextError = const DatabaseFailure();

      await _choose(tester, 'Currency', 'Euro (EUR)');

      expect(find.text('Settings saved.'), findsNothing);
      expect(
        find.text(const DatabaseFailure().message),
        findsOneWidget,
        reason: 'the error is shown in place of a false success',
      );
      expect(AppFormatters.preferences.currencyCode, 'INR');
    });
  });

  group('date and number formats', () {
    testWidgets(
      'are saved and used for every date and amount after a restart',
      (WidgetTester tester) async {
        await account.launch(tester);
        await _openSettings(tester);

        await _choose(tester, 'Date format', '2026-10-08');
        await _choose(tester, 'Number format', '100,000.00');
        await _choose(tester, 'First day of the week', 'Sunday');

        expect(account.userSettings.settings.dateFormat, 'yyyy-MM-dd');
        expect(account.userSettings.settings.numberFormat, 'international');
        expect(account.userSettings.settings.firstDayOfWeek, 'sunday');

        await account.launch(tester);
        expect(AppFormatters.date(DateTime(2026, 10, 8)), '2026-10-08');
        expect(AppFormatters.number(100000), '100,000.00');
        expect(AppFormatters.preferences.weekStart, WeekStart.sunday);
      },
    );
  });

  group('default account', () {
    testWidgets('pre-selects the chosen account on a new transaction', (
      WidgetTester tester,
    ) async {
      account.userSettings.settings = const UserSettings(
        dateFormat: null,
        numberFormat: null,
        firstDayOfWeek: 'monday',
        languageCode: 'en',
        defaultAccountId: 'acc-2',
      );
      await account.launch(tester);

      unawaited(
        Get.toNamed<void>(
          AppRoutes.transactionForm,
          arguments: const TransactionFormArgs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TransactionFormView), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);
    });

    testWidgets('without a default the first account is used', (
      WidgetTester tester,
    ) async {
      await account.launch(tester);

      unawaited(
        Get.toNamed<void>(
          AppRoutes.transactionForm,
          arguments: const TransactionFormArgs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cash'), findsOneWidget);
    });

    testWidgets('a default that was deleted falls back to the first account', (
      WidgetTester tester,
    ) async {
      account.userSettings.settings = const UserSettings(
        dateFormat: null,
        numberFormat: null,
        firstDayOfWeek: 'monday',
        languageCode: 'en',
        defaultAccountId: 'gone-account',
      );
      await account.launch(tester);

      unawaited(
        Get.toNamed<void>(
          AppRoutes.transactionForm,
          arguments: const TransactionFormArgs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cash'), findsOneWidget);
    });
  });

  group('sign-out and the next user', () {
    testWidgets(
      'signing out clears the user data and the next user gets theirs',
      (WidgetTester tester) async {
        account.profiles.profile = const Profile(
          id: 'user-1',
          fullName: 'Asha Rao',
          currencyCode: 'USD',
          timezone: 'Asia/Kolkata',
        );
        await account.launch(tester);
        expect(AppFormatters.preferences.currencyCode, 'USD');
        final ProfileController signedInUsers = Get.find<ProfileController>();

        await _openSettings(tester);
        await tapAndSettle(tester, find.text('Sign out of this device'));

        expect(find.byType(LoginView), findsOneWidget);
        // Fenix controllers are disposed and rebuilt on next use, so the
        // user's instance must not be the one found now.
        expect(
          identical(Get.find<ProfileController>(), signedInUsers),
          isFalse,
        );
        expect(AppFormatters.preferences, UserPreferences.defaults);
        // Controllers that hold one user's data are gone, not just emptied.
        expect(Get.isRegistered<HomeController>(), isFalse);
        expect(Get.isRegistered<BudgetController>(), isFalse);
        expect(Get.isRegistered<ReminderController>(), isFalse);
        expect(
          Get.find<SettingsController>().preferences.value,
          UserPreferences.defaults,
        );

        // A protected screen is out of reach until someone signs in again.
        unawaited(Get.toNamed<void>(AppRoutes.profile));
        await tester.pumpAndSettle();
        expect(find.byType(LoginView), findsOneWidget);

        // Another user signs in on the same device.
        account.profiles.profile = const Profile(
          id: 'user-2',
          fullName: 'Ravi Menon',
          currencyCode: 'EUR',
          timezone: 'Europe/Berlin',
        );
        account.auth.emit(AuthStatus.signedIn);
        await tester.pumpAndSettle();

        expect(AppFormatters.preferences.currencyCode, 'EUR');
      },
    );
  });

  group('region loading', () {
    testWidgets('a failed load says so, keeps appearance, and retries', (
      WidgetTester tester,
    ) async {
      account.userSettings.nextError = const NetworkFailure();
      await account.launch(tester);
      await _openSettings(tester);

      expect(find.text(const NetworkFailure().message), findsOneWidget);
      expect(
        find.text('Dark'),
        findsOneWidget,
        reason: 'appearance still works',
      );

      await tapAndSettle(tester, find.text('Try again'));
      expect(find.text('Currency'), findsOneWidget);
    });
  });

  group('language and information', () {
    testWidgets('only English is offered, and more is said to be coming', (
      WidgetTester tester,
    ) async {
      await account.launch(tester);
      await _openSettings(tester);

      expect(find.text('More languages are coming'), findsOneWidget);
      await tapAndSettle(tester, find.text('Language'));
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('the policy pages say they are placeholders', (
      WidgetTester tester,
    ) async {
      await account.launch(tester);
      await _openSettings(tester);

      await tapAndSettle(tester, find.text('Privacy policy'));
      expect(find.byType(PolicyView), findsOneWidget);
      expect(find.textContaining('placeholder'), findsOneWidget);
      Get.back<void>();
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.text('Terms of service'));
      expect(find.byType(PolicyView), findsOneWidget);
      expect(find.textContaining('placeholder'), findsOneWidget);
    });

    testWidgets('about shows the version', (WidgetTester tester) async {
      await account.launch(tester);
      await _openSettings(tester);

      await tapAndSettle(tester, find.text('About'));
      expect(find.byType(AboutView), findsOneWidget);
      expect(find.text('Version 1.0.0'), findsWidgets);
    });
  });
}
