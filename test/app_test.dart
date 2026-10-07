import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/features/dashboard/views/dashboard_view.dart';
import 'package:finance_tracker/features/settings/views/settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'helpers/fakes.dart';

Brightness _brightnessOf(WidgetTester tester, Type view) =>
    Theme.of(tester.element(find.byType(view))).brightness;

void main() {
  tearDown(Get.reset);

  test('both themes register FinanceColors', () {
    expect(AppTheme.light.extension<FinanceColors>(), FinanceColors.light);
    expect(AppTheme.dark.extension<FinanceColors>(), FinanceColors.dark);
  });

  testWidgets('starts on the dashboard and navigates to settings and back', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
    expect(find.byType(DashboardView), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DashboardView), findsOneWidget);
    expect(find.byType(SettingsView), findsNothing);
  });

  testWidgets('switching theme mode changes the app brightness', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
    await tester.tap(find.text('Appearance settings'));
    await tester.pumpAndSettle();
    expect(_brightnessOf(tester, SettingsView), Brightness.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(_brightnessOf(tester, SettingsView), Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(_brightnessOf(tester, SettingsView), Brightness.light);
  });
}
