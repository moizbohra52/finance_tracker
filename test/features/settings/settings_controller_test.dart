import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

void main() {
  late FakeFinance finance;
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeUserSettingsRepository userSettings;
  late DataChangeNotifier notifier;
  late SettingsController controller;

  SettingsController build() => SettingsController(
    profiles,
    userSettings,
    finance.repositories.accounts,
    auth,
    notifier,
  );

  setUp(() {
    finance = FakeFinance()
      ..addAccount('Cash', '0')
      ..addAccount('Bank', '0', id: 'acc-2');
    auth = FakeAuthRepository(signedIn: true);
    profiles = FakeProfileRepository();
    userSettings = FakeUserSettingsRepository();
    notifier = DataChangeNotifier();
    controller = build();
  });

  tearDown(() => AppFormatters.preferences = UserPreferences.defaults);

  group('loading', () {
    test(
      'reads the saved values and makes them the formatting defaults',
      () async {
        userSettings.settings = const UserSettings(
          dateFormat: 'dd/MM/yyyy',
          numberFormat: 'international',
          firstDayOfWeek: 'sunday',
          languageCode: 'en',
          defaultAccountId: 'acc-2',
        );
        await controller.load();

        expect(
          controller.preferences.value.dateStyle,
          DateStyle.dayMonthNumeric,
        );
        expect(
          controller.preferences.value.numberStyle,
          NumberStyle.international,
        );
        expect(controller.preferences.value.weekStart, WeekStart.sunday);
        expect(controller.preferences.value.defaultAccountId, 'acc-2');
        expect(AppFormatters.preferences, controller.preferences.value);
        expect(controller.accounts.map((account) => account.id), <String>[
          'acc-1',
          'acc-2',
        ]);
      },
    );

    test('a value the app does not know falls back to the default', () async {
      userSettings.settings = const UserSettings(
        dateFormat: 'not a pattern',
        numberFormat: null,
        firstDayOfWeek: 'friday',
        languageCode: null,
        defaultAccountId: null,
      );
      await controller.load();

      expect(controller.preferences.value.dateStyle, DateStyle.dayMonthYear);
      expect(controller.preferences.value.numberStyle, NumberStyle.indian);
      expect(controller.preferences.value.weekStart, WeekStart.monday);
      expect(controller.preferences.value.languageCode, 'en');
    });

    test('a failed load shows the error and keeps the defaults', () async {
      userSettings.nextError = const NetworkFailure();
      await controller.load();

      expect(controller.loadError.value, const NetworkFailure().message);
      expect(controller.preferences.value, UserPreferences.defaults);
      expect(controller.isLoading.value, isFalse);
    });

    test('a signed-out start does not load anything', () async {
      auth = FakeAuthRepository();
      controller = build();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isLoading.value, isTrue);
      expect(controller.accounts, isEmpty);
    });
  });

  group('saving', () {
    test(
      'writes the currency to the profile and the rest to user settings',
      () async {
        await controller.load();
        final bool saved = await controller.savePreferences(
          controller.preferences.value.copyWith(
            currencyCode: 'USD',
            dateStyle: DateStyle.isoDate,
            weekStart: WeekStart.sunday,
            defaultAccountId: 'acc-2',
          ),
        );

        expect(saved, isTrue);
        expect(profiles.profile.currencyCode, 'USD');
        final UserSettings written = userSettings.writes.single;
        expect(written.dateFormat, 'yyyy-MM-dd');
        expect(written.firstDayOfWeek, 'sunday');
        expect(written.defaultAccountId, 'acc-2');
        expect(AppFormatters.preferences.currencyCode, 'USD');
        expect(notifier.version.value, 1, reason: 'other screens reload');
      },
    );

    test('an unchanged currency is not written to the profile again', () async {
      await controller.load();
      profiles.failUpdates = true;

      final bool saved = await controller.savePreferences(
        controller.preferences.value.copyWith(
          numberStyle: NumberStyle.international,
        ),
      );
      expect(saved, isTrue, reason: 'only the user settings row changed');
    });

    test('clearing the default account writes an explicit null', () async {
      userSettings.settings = const UserSettings(
        dateFormat: null,
        numberFormat: null,
        firstDayOfWeek: 'monday',
        languageCode: 'en',
        defaultAccountId: 'acc-2',
      );
      await controller.load();
      await controller.savePreferences(
        controller.preferences.value.copyWith(clearDefaultAccount: true),
      );
      expect(userSettings.writes.single.toJson()['default_account_id'], isNull);
    });

    test('if the profile write fails nothing is saved or shown', () async {
      await controller.load();
      profiles.nextError = const DatabaseFailure();

      final bool saved = await controller.savePreferences(
        controller.preferences.value.copyWith(currencyCode: 'EUR'),
      );

      expect(saved, isFalse);
      expect(controller.save.error.value, const DatabaseFailure().message);
      expect(userSettings.writes, isEmpty);
      expect(controller.preferences.value.currencyCode, 'INR');
      expect(AppFormatters.preferences.currencyCode, 'INR');
      expect(notifier.version.value, 0);
    });

    test('if the second write fails the screen shows what the server holds, '
        'not the value that was rejected', () async {
      await controller.load();
      // The currency write goes through; the settings row write fails.
      userSettings.nextError = const DatabaseFailure();

      final bool saved = await controller.savePreferences(
        controller.preferences.value.copyWith(
          currencyCode: 'USD',
          dateStyle: DateStyle.isoDate,
        ),
      );

      expect(saved, isFalse);
      expect(profiles.profile.currencyCode, 'USD', reason: 'first write held');
      // Reloaded from the server: currency is USD, the date style never saved.
      expect(controller.preferences.value.currencyCode, 'USD');
      expect(controller.preferences.value.dateStyle, DateStyle.dayMonthYear);
      expect(AppFormatters.preferences.dateStyle, DateStyle.dayMonthYear);
    });
  });

  group('reset at sign-out', () {
    test('clears the values and the formatting defaults', () async {
      await controller.load();
      await controller.savePreferences(
        controller.preferences.value.copyWith(
          currencyCode: 'GBP',
          numberStyle: NumberStyle.international,
        ),
      );
      expect(AppFormatters.preferences.currencyCode, 'GBP');

      controller.reset();

      expect(controller.preferences.value, UserPreferences.defaults);
      expect(AppFormatters.preferences, UserPreferences.defaults);
      expect(controller.accounts, isEmpty);
      expect(controller.save.error.value, isNull);
    });
  });
}
