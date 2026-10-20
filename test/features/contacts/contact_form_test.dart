import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/features/contacts/services/device_contacts_service.dart';
import 'package:finance_tracker/features/contacts/views/contact_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';

void main() {
  late FakeFinance fakeFinance;
  late ContactFormController controller;

  setUp(() {
    Get.testMode = true;
    fakeFinance = FakeFinance();
    controller = ContactFormController(
      fakeFinance.repositories.contacts,
      fakeFinance.repositories.transactions,
      fakeFinance.repositories.accounts,
      DataChangeNotifier(),
    );
    Get.put<ContactFormController>(controller);
  });

  tearDown(() {
    Get.reset();
  });

  Widget buildTestApp() {
    return GetMaterialApp(
      initialRoute: '/home',
      getPages: <GetPage<void>>[
        GetPage<void>(
          name: '/home',
          page: () => const Scaffold(body: SizedBox.shrink()),
        ),
        GetPage<void>(
          name: AppRoutes.contactForm,
          page: () => const ContactFormView(),
        ),
      ],
    );
  }

  testWidgets('renders add contact form with single mobile field initially', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildTestApp());
    Get.toNamed<void>(AppRoutes.contactForm)?.ignore();
    await tester.pumpAndSettle();

    expect(find.text('Add contact'), findsOneWidget);
    expect(find.text('Pick from Phone Contacts'), findsOneWidget);
    expect(find.text('Mobile (optional)'), findsOneWidget);
    expect(find.text('Add another mobile number'), findsOneWidget);
  });

  testWidgets('can add and remove dynamic mobile number fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildTestApp());
    Get.toNamed<void>(AppRoutes.contactForm)?.ignore();
    await tester.pumpAndSettle();

    // Tap to add another mobile number
    await tester.tap(find.text('Add another mobile number'));
    await tester.pumpAndSettle();

    // Now there should be Mobile 1 and Mobile 2 labels
    expect(find.text('Mobile 1 (optional)'), findsOneWidget);
    expect(find.text('Mobile 2 (optional)'), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline_rounded), findsNWidgets(2));

    // Tap remove button on second number
    await tester.tap(find.byIcon(Icons.remove_circle_outline_rounded).last);
    await tester.pumpAndSettle();

    // Reverts back to single Mobile label
    expect(find.text('Mobile (optional)'), findsOneWidget);
  });

  testWidgets('pre-fills details and multiple numbers from initialDeviceContact', (
    WidgetTester tester,
  ) async {
    const DeviceContactData mockContact = DeviceContactData(
      id: 'mock_1',
      displayName: 'Vikram Singh',
      phones: <String>['+919876543210', '+919123456789'],
      email: 'vikram@example.com',
      address: 'Shop 12, Main Bazaar',
      notes: 'Hardware Vendor',
    );

    await tester.pumpWidget(buildTestApp());
    Get.toNamed<void>(
      AppRoutes.contactForm,
      arguments: <String, dynamic>{'initialDeviceContact': mockContact},
    )?.ignore();
    await tester.pumpAndSettle();

    // Verify name, email, address, notes are autofilled
    expect(find.text('Vikram Singh'), findsOneWidget);
    expect(find.text('vikram@example.com'), findsOneWidget);
    expect(find.text('Shop 12, Main Bazaar'), findsOneWidget);
    expect(find.text('Hardware Vendor'), findsOneWidget);

    // Verify both numbers are populated into separate fields
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('+919123456789'), findsOneWidget);
    expect(find.text('Mobile 1 (optional)'), findsOneWidget);
    expect(find.text('Mobile 2 (optional)'), findsOneWidget);
  });
}
