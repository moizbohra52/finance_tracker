import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

void main() {
  late FakeUserSettingsRepository userSettings;
  late SettingsController controller;

  setUpAll(() => initializeDateFormatting('hi_IN'));

  setUp(() {
    Get.testMode = true;
    userSettings = FakeUserSettingsRepository();
    controller = SettingsController(
      FakeProfileRepository(),
      userSettings,
      (FakeFinance()..addAccount('Cash', '0')).repositories.accounts,
      FakeAuthRepository(signedIn: true),
      DataChangeNotifier(),
    );
  });

  tearDown(() {
    AppFormatters.preferences = UserPreferences.defaults;
    Get.locale = AppLanguage.english.locale;
  });

  UserSettings withLanguage(String? code) => UserSettings(
    dateFormat: 'd MMM y',
    numberFormat: 'indian',
    firstDayOfWeek: 'monday',
    languageCode: code,
    defaultAccountId: null,
  );

  test('stored codes map to languages, anything else is English', () {
    expect(AppLanguage.fromStored('hi'), AppLanguage.hindi);
    expect(AppLanguage.fromStored('hi-Latn'), AppLanguage.hinglish);
    expect(AppLanguage.fromStored('en'), AppLanguage.english);
    expect(AppLanguage.fromStored('fr'), AppLanguage.english);
    expect(AppLanguage.fromStored(null), AppLanguage.english);
  });

  testWidgets('a saved Hindi account loads in Hindi', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox.shrink()));
    userSettings.settings = withLanguage('hi');
    await controller.load();
    await tester.pump(Duration.zero); // runs the rebuild

    expect(controller.preferences.value.language, AppLanguage.hindi);
    expect(Get.locale, const Locale('hi', 'IN'));
  });

  testWidgets('saving Hinglish writes hi-Latn', (WidgetTester tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox.shrink()));
    await controller.load();
    final bool saved = await controller.savePreferences(
      controller.preferences.value.copyWith(language: AppLanguage.hinglish),
    );
    await tester.pump(Duration.zero);

    expect(saved, isTrue);
    expect(userSettings.writes.single.languageCode, 'hi-Latn');
    expect(Get.locale, const Locale('hi', 'Latn'));
  });

  testWidgets('a save the repository refuses keeps the previous language', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox.shrink()));
    await controller.load();
    userSettings.nextError = const DatabaseFailure();

    final bool saved = await controller.savePreferences(
      controller.preferences.value.copyWith(language: AppLanguage.hindi),
    );

    expect(saved, isFalse);
    expect(controller.preferences.value.language, AppLanguage.english);
    expect(Get.locale, const Locale('en', 'IN'));
  });

  testWidgets('reset at sign-out returns to English', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox.shrink()));
    userSettings.settings = withLanguage('hi');
    await controller.load();
    controller.reset();
    await tester.pump(Duration.zero);

    expect(controller.preferences.value.language, AppLanguage.english);
    expect(Get.locale, const Locale('en', 'IN'));
  });

  test('Hindi dates use Hindi month names', () {
    AppFormatters.preferences = const UserPreferences(
      language: AppLanguage.hindi,
    );
    expect(
      AppFormatters.date(DateTime(2026, 10, 8), pattern: 'd MMMM y'),
      '8 अक्टूबर 2026',
    );
  });
}
