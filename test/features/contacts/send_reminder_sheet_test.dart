import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/translations/app_translations.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/contacts/views/send_reminder_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  tearDown(() {
    Get.locale = AppLanguage.english.locale;
    AppFormatters.preferences = UserPreferences.defaults;
  });

  Future<void> openSheet(WidgetTester tester, AppLanguage language) async {
    AppFormatters.preferences = UserPreferences.defaults.copyWith(
      language: language,
    );
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light,
        translations: AppTranslations(),
        locale: language.locale,
        home: Scaffold(
          body: SendReminderSheet(
            contact: Contact(
              id: 'c1',
              userId: 'u1',
              name: 'Ravi',
              mobile: '9876543210',
              openingBalance: Decimal.zero,
              openingBalanceType: 'receivable',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
            balance: Decimal.parse('250'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String message(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).last).controller!.text;

  for (final (AppLanguage language, String greeting)
      in <(AppLanguage, String)>[
        (AppLanguage.english, 'Dear Ravi,'),
        (AppLanguage.hindi, 'नमस्ते Ravi जी,'),
        (AppLanguage.hinglish, 'Namaste Ravi ji,'),
      ]) {
    testWidgets('in ${language.label} the message starts in that language', (
      WidgetTester tester,
    ) async {
      await openSheet(tester, language);
      expect(message(tester), startsWith(greeting));
    });
  }

  testWidgets('another language can be chosen before sending', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, AppLanguage.english);

    await tester.tap(find.widgetWithText(ChoiceChip, 'हिंदी'));
    await tester.pumpAndSettle();
    expect(message(tester), startsWith('नमस्ते Ravi जी,'));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Hinglish'));
    await tester.pumpAndSettle();
    expect(message(tester), startsWith('Namaste Ravi ji,'));
  });
}
