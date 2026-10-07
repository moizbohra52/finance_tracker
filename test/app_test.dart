import 'dart:async';

import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/theme/app_accent_color.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/features/dashboard/views/app_shell_view.dart';
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

  testWidgets('shell switches among its five destinations', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
    expect(find.byType(AppShellView), findsOneWidget);
    expect(find.byType(DashboardView), findsOneWidget);

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('No transactions yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    expect(find.text('No contacts yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(find.text('This month'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Personal details'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardView), findsOneWidget);
  });

  testWidgets('wide shell uses a navigation rail', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('offline banner follows connectivity transitions', (
    WidgetTester tester,
  ) async {
    final StreamController<NetworkStatus> events =
        StreamController<NetworkStatus>.broadcast();
    addTearDown(events.close);
    final ConnectivityService connectivity = ConnectivityService.forTest(
      watch: () => events.stream,
      check: () async => NetworkStatus.online,
    );
    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true),
      connectivityService: connectivity,
    );
    expect(find.byType(OfflineBanner), findsNothing);

    events.add(NetworkStatus.offline);
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBanner), findsOneWidget);

    events.add(NetworkStatus.online);
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBanner), findsNothing);
  });

  testWidgets('switching theme mode changes the app brightness', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(_brightnessOf(tester, SettingsView), Brightness.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(_brightnessOf(tester, SettingsView), Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(_brightnessOf(tester, SettingsView), Brightness.light);
  });

  testWidgets('accent selection rebuilds the app theme', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
    final Color original = Theme.of(
      tester.element(find.byType(DashboardView)),
    ).colorScheme.primary;
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppAccentColor.teal.label));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(SettingsView))).colorScheme.primary,
      isNot(original),
    );
  });
}
