import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/core/translations/hinglish.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

void main() {
  late FakeUserSettingsRepository userSettings;

  setUp(() => userSettings = FakeUserSettingsRepository());

  tearDown(() {
    Get.reset();
    Get.locale = AppLanguage.english.locale;
    AppFormatters.preferences = UserPreferences.defaults;
  });

  Future<void> start(WidgetTester tester) => pumpApp(
    tester,
    auth: FakeAuthRepository(signedIn: true),
    userSettings: userSettings,
    finance: FakeFinance()..addAccount('Cash', '0'),
  );

  Finder navLabel(String text) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(text),
  );

  testWidgets('choosing Hindi changes the open screens', (
    WidgetTester tester,
  ) async {
    await start(tester);
    unawaited(Get.toNamed<void>(AppRoutes.settings));
    await tester.pumpAndSettle();

    await tapAndSettle(tester, find.text('Language'));
    await tapAndSettle(tester, find.text('हिंदी'));
    expect(userSettings.writes.last.languageCode, 'hi');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(navLabel(hindi['Home']!), findsOneWidget);
    expect(navLabel(hindi['Khata']!), findsOneWidget);
    expect(navLabel('Home'), findsNothing);
  });

  testWidgets('a Hinglish account opens in Hinglish and lays out', (
    WidgetTester tester,
  ) async {
    userSettings.settings = const UserSettings(
      dateFormat: 'd MMM y',
      numberFormat: 'indian',
      firstDayOfWeek: 'monday',
      languageCode: 'hi-Latn',
      defaultAccountId: null,
    );
    await start(tester);
    await tester.pumpAndSettle();
    expect(navLabel(hinglish['Transactions']!), findsOneWidget);

    unawaited(Get.toNamed<void>(AppRoutes.settings));
    await tester.pumpAndSettle();
    expect(find.text(hinglish['Region and format']!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hindi reaches transactions, the form and khata', (
    WidgetTester tester,
  ) async {
    userSettings.settings = const UserSettings(
      dateFormat: 'd MMM y',
      numberFormat: 'indian',
      firstDayOfWeek: 'monday',
      languageCode: 'hi',
      defaultAccountId: null,
    );
    await start(tester);
    await tester.pumpAndSettle();

    await tapAndSettle(tester, navLabel(hindi['Transactions']!));
    expect(
      find.text(hindi['Record your income and expenses to see them here.']!),
      findsOneWidget,
    );

    await tapAndSettle(tester, navLabel(hindi['Khata']!));
    expect(
      find.text(
        hindi['Add the people you lend to or borrow from, then record credit and debit entries against them.']!,
      ),
      findsOneWidget,
    );

    unawaited(Get.toNamed<void>(AppRoutes.transactionForm));
    await tester.pumpAndSettle();
    expect(find.text(hindi['Note (optional)']!), findsOneWidget);
    await tapAndSettle(tester, find.text(hindi['Save']!));
    // The error is under the amount field, scrolled off by the tap on Save.
    await tester.scrollUntilVisible(
      find.text(hindi['Enter an amount']!),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(hindi['Enter an amount']!), findsOneWidget);
  });

  testWidgets('Hindi reaches accounts, budgets, recurring and reminders', (
    WidgetTester tester,
  ) async {
    userSettings.settings = const UserSettings(
      dateFormat: 'd MMM y',
      numberFormat: 'indian',
      firstDayOfWeek: 'monday',
      languageCode: 'hi',
      defaultAccountId: null,
    );
    await start(tester);
    await tester.pumpAndSettle();

    for (final (String route, String text) in <(String, String)>[
      (AppRoutes.accounts, hindi['Add account']!),
      (AppRoutes.budgets, hindi['No budgets yet']!),
      (AppRoutes.recurring, hindi['No recurring transactions']!),
      (AppRoutes.reminders, hindi['No reminders']!),
    ]) {
      unawaited(Get.toNamed<void>(route));
      await tester.pumpAndSettle();
      expect(find.text(text), findsWidgets, reason: route);
      Get.back<void>();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('in Hindi each mobile number keeps its WhatsApp button', (
    WidgetTester tester,
  ) async {
    userSettings.settings = const UserSettings(
      dateFormat: 'd MMM y',
      numberFormat: 'indian',
      firstDayOfWeek: 'monday',
      languageCode: 'hi',
      defaultAccountId: null,
    );
    final FakeFinance finance = FakeFinance()..addAccount('Cash', '0');
    finance.contacts.add(
      Contact(
        id: 'c1',
        userId: 'u1',
        name: 'Ravi',
        mobile: '9876543210, 9123456780',
        openingBalance: Decimal.zero,
        openingBalanceType: 'receivable',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true),
      userSettings: userSettings,
      finance: finance,
    );
    await tester.pumpAndSettle();
    unawaited(Get.toNamed<void>(AppRoutes.contactDetail, arguments: 'c1'));
    await tester.pumpAndSettle();

    final Finder whatsApp = find.byTooltip(
      hindi['Send reminder via WhatsApp']!,
    );
    await tester.dragUntilVisible(
      find.text(hindi['Details']!),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(whatsApp, findsNWidgets(2));
  });

  testWidgets('a long quick action label is shown whole', (
    WidgetTester tester,
  ) async {
    // The test font is 1em per letter: at this width 'Udhaar diya' needs two
    // lines, as it does on a 360dp phone.
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    userSettings.settings = const UserSettings(
      dateFormat: 'd MMM y',
      numberFormat: 'indian',
      firstDayOfWeek: 'monday',
      languageCode: 'hi-Latn',
      defaultAccountId: null,
    );
    await start(tester);
    await tester.pumpAndSettle();

    final RenderParagraph credit = tester.renderObject(
      find.text(hinglish['Credit']!),
    );
    expect(credit.didExceedMaxLines, isFalse);
  });

  testWidgets('English stays English', (WidgetTester tester) async {
    await start(tester);

    expect(navLabel('Home'), findsOneWidget);
    expect(navLabel('Transactions'), findsOneWidget);
  });
}
