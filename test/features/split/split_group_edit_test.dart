import 'dart:async';

import 'package:finance_tracker/features/split/views/split_group_detail_view.dart';
import 'package:finance_tracker/features/split/views/split_group_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';
import 'split_group_views_test.dart' show dinner;

void main() {
  tearDown(Get.reset);

  testWidgets('editing a group from its detail renames it', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);

    unawaited(Get.toNamed<void>(AppRoutes.splitGroupDetail, arguments: 'g1'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitGroupDetailView), findsOneWidget);

    await tester.tap(find.byTooltip('Edit group'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitGroupFormView), findsOneWidget);
    expect(find.text('Amit'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Goa trip');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(SplitGroupFormView), findsNothing);
    expect(find.text('Group updated'), findsOneWidget);
    expect(find.text('Goa trip'), findsWidgets);
    expect(f.splitGroups.single.name, 'Goa trip');
  });
}
