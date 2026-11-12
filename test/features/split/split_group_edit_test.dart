import 'dart:async';
import 'dart:io';

import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/data/repositories/photo_store.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/features/split/controllers/split_group_controller.dart';
import 'package:finance_tracker/features/split/views/split_group_detail_view.dart';
import 'package:finance_tracker/features/split/views/split_group_form_view.dart';
import 'package:finance_tracker/features/split/views/split_group_list_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/entity_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';
import 'split_group_views_test.dart' show dinner;

/// A photo store with no network and no disk: it only records removals. The
/// photo sheet itself (View / Take / Choose) needs the camera and gallery
/// plugins, so only Remove, which needs neither, is driven here.
class _FakePhotoStore extends PhotoStore {
  _FakePhotoStore() : super(null);

  final List<String> removed = <String>[];

  @override
  Future<File?> file(String path) async => null;

  @override
  Future<void> remove(String path) async => removed.add(path);
}

const String _photo = 'u/groups/g1-1.jpg';

Future<SplitGroupSummary> _summary(FakeFinance f) async =>
    (await f.repositories.split.getGroups()).single;

Future<void> _openForm(WidgetTester tester, [SplitGroupSummary? edit]) async {
  unawaited(Get.toNamed<void>(AppRoutes.splitGroupForm, arguments: edit));
  await tester.pumpAndSettle();
}

Finder _photoControl() => find.descendant(
  of: find.byType(SplitGroupFormView),
  matching: find.byType(EditablePhoto),
);

void main() {
  tearDown(Get.reset);

  testWidgets('editing shows the group photo control, creating does not', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);

    await _openForm(tester, await _summary(f));
    expect(_photoControl(), findsOneWidget);
    expect(
      find.text('You can add a group photo after creating the group.'),
      findsNothing,
    );
    Get.back<void>();
    await tester.pumpAndSettle();

    await _openForm(tester);
    expect(_photoControl(), findsNothing);
    expect(
      find.text('You can add a group photo after creating the group.'),
      findsOneWidget,
    );
  });

  testWidgets('a photo set through the controller is stored on the group', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
    await _openForm(tester, await _summary(f));

    await Get.find<SplitGroupController>().setGroupPhoto('g1', _photo);
    await tester.pumpAndSettle();

    expect(f.splitGroups.single.avatarPath, _photo);
  });

  testWidgets('with a photo the sheet offers Remove; confirming clears it', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await f.repositories.split.setGroupPhoto('g1', _photo);
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
    final _FakePhotoStore store =
        Get.put<PhotoStore>(_FakePhotoStore()) as _FakePhotoStore;
    await _openForm(tester, await _summary(f));

    await tester.tap(_photoControl());
    await tester.pumpAndSettle();
    expect(find.text('Remove photo'), findsOneWidget);

    // Cancel keeps it.
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(find.text('Remove the photo?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(f.splitGroups.single.avatarPath, _photo);

    await tester.tap(_photoControl());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(f.splitGroups.single.avatarPath, isNull);
    expect(store.removed, <String>[_photo]);
    // The form's own state followed: the sheet no longer offers Remove.
    await tester.tap(_photoControl());
    await tester.pumpAndSettle();
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('the group card menu opens the edit form for that group', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
    unawaited(Get.toNamed<void>(AppRoutes.splitGroups));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit group'));
    await tester.pumpAndSettle();

    expect(find.byType(SplitGroupFormView), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Goa',
    );
  });

  testWidgets('the card keeps opening the detail on tap', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
    unawaited(Get.toNamed<void>(AppRoutes.splitGroups));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Goa'));
    await tester.pumpAndSettle();

    expect(find.byType(SplitGroupDetailView), findsOneWidget);
  });

  testWidgets('a card with its own tap (the chooser) has no menu', (
    WidgetTester tester,
  ) async {
    final FakeFinance f = await dinner();
    await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), finance: f);
    final SplitGroupSummary summary = await _summary(f);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SplitGroupCard(summary: summary, onTap: () {}),
        ),
      ),
    );

    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

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
