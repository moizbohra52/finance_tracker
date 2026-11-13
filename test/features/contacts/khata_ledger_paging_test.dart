import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/export_service.dart';
import 'package:finance_tracker/core/services/file_sharing_service.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_detail_controller.dart';
import 'package:finance_tracker/features/contacts/views/contact_detail_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

/// Records how many entries the statement was built from.
class _CountingExport extends ExportService {
  int? entries;

  @override
  Future<List<int>> generateContactStatementPdf({
    required Contact contact,
    required List<ContactTransaction> entries,
    String? userName,
    String? upiPayLink,
    String currencyCode = 'INR',
  }) async {
    this.entries = entries.length;
    return '%PDF-'.codeUnits;
  }
}

class _NoSharing extends FileSharingService {
  @override
  Future<ShareResult> saveAndShareBytes({
    required String fileName,
    required List<int> bytes,
    String? mimeType,
    String? subject,
  }) async => const ShareResult('success', ShareResultStatus.success);
}

/// Ravi, who owed 1,000 at the start, with 70 credits of 10 and 5 payments
/// back of 20, each on its own day: 75 entries, balance 1,000 + 700 - 100.
FakeFinance _ravi() {
  final FakeFinance f = FakeFinance();
  f.contacts.add(
    Contact(
      id: 'c-ravi',
      userId: 'user-1',
      name: 'Ravi',
      mobile: '9876543210',
      openingBalance: Decimal.parse('1000'),
      openingBalanceType: 'receivable',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  );
  ContactTransaction entry(String id, ContactTransactionType type, int day) =>
      ContactTransaction(
        id: id,
        userId: 'user-1',
        contactId: 'c-ravi',
        type: type,
        amount: Decimal.parse(
          type == ContactTransactionType.credit ? '10' : '20',
        ),
        transactionDate: DateTime(2026).add(Duration(days: day)),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
  for (int i = 0; i < 70; i++) {
    f.contactTransactions.add(
      entry('credit-$i', ContactTransactionType.credit, i),
    );
  }
  for (int i = 0; i < 5; i++) {
    f.contactTransactions.add(
      entry('paid-$i', ContactTransactionType.paymentReceived, 100 + i),
    );
  }
  return f;
}

ContactDetailController _controller(
  FakeFinance f, {
  ExportService export = const ExportService(),
}) => ContactDetailController(
  f.repositories.contacts,
  f.repositories.transactions,
  DataChangeNotifier(),
  'c-ravi',
  exportService: export,
  sharingService: _NoSharing(),
);

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  test('loads a page at a time and still shows the full balance', () async {
    final ContactDetailController c = _controller(_ravi());
    await c.load();
    expect(c.entries.length, ContactDetailController.pageSize);
    expect(c.hasMore.value, isTrue);
    // Newest first: the payments back come before the credits.
    expect(c.entries.first.id, 'paid-4');
    expect(c.balance.value, Decimal.parse('1600'));

    await c.loadMore();
    await c.loadMore();
    expect(c.entries.length, 75);
    expect(c.hasMore.value, isFalse);
    expect(
      c.entries.map((ContactTransaction e) => e.id).toSet(),
      hasLength(75),
    );

    // A silent reload keeps every loaded entry, so the list does not jump.
    await c.load(silent: true);
    expect(c.entries.length, 75);
  });

  test(
    'the statement covers the whole ledger, not just the loaded page',
    () async {
      final _CountingExport export = _CountingExport();
      final ContactDetailController c = _controller(_ravi(), export: export);
      await c.load();
      expect(c.entries.length, ContactDetailController.pageSize);

      expect(await c.shareStatement(), isTrue);
      expect(export.entries, 75);
    },
  );

  testWidgets('scrolling the screen loads the rest, then the details', (
    WidgetTester tester,
  ) async {
    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true),
      finance: _ravi(),
    );
    unawaited(Get.toNamed<void>(AppRoutes.contactDetail, arguments: 'c-ravi'));
    await tester.pumpAndSettle();
    expect(find.byType(ContactDetailView), findsOneWidget);
    final ContactDetailController c = Get.find<ContactDetailController>(
      tag: 'c-ravi',
    );
    expect(c.entries.length, ContactDetailController.pageSize);
    expect(find.text('Details'), findsNothing, reason: 'not all loaded yet');

    final Finder list = find.byType(Scrollable).first;
    for (int i = 0; i < 60 && find.text('Details').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(c.entries.length, 75);
    expect(find.text('Details'), findsOneWidget);
  });

  test('deleting the contact removes every entry, loaded or not', () async {
    final FakeFinance f = _ravi();
    final ContactDetailController c = _controller(f);
    Get.put(c);
    await c.load();
    expect(c.entries.length, ContactDetailController.pageSize);

    expect(await c.deleteContact(), isTrue);
    expect(
      f.contactTransactions.where(
        (ContactTransaction e) => e.contactId == 'c-ravi',
      ),
      isEmpty,
    );
  });
}
