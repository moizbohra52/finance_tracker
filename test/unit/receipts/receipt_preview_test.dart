import 'dart:io';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/data/repositories/receipt_store.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/widgets/receipt_field.dart';
import 'package:finance_tracker/features/transactions/widgets/receipt_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fake_receipts.dart';

/// The phone's copy comes from memory: ReceiptStore's file handling has its
/// own tests, and real file IO does not run under the widget test clock.
class _PreviewStore extends FakeReceiptStore {
  _PreviewStore()
    : super(FakeFinance().repositories.transactions, Directory(''));

  Uint8List? local;
  bool pending = false;

  @override
  Future<Uint8List?> localBytes(String txId) async => local;

  @override
  Future<bool> isPending(String txId) async => pending;
}

Transaction _tx({String? attachmentUrl, DateTime? updatedAt}) => Transaction(
  id: 'tx-1',
  userId: 'user-1',
  accountId: 'acc-1',
  type: TransactionType.expense,
  amount: Decimal.parse('50'),
  transactionDate: DateTime(2026, 10, 21),
  attachmentUrl: attachmentUrl,
  createdAt: DateTime(2026, 10, 21),
  updatedAt: updatedAt ?? DateTime(2026, 10, 21),
);

/// The bytes the preview's image shows.
Uint8List _shown(WidgetTester tester) =>
    (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes;

void main() {
  late _PreviewStore store;

  setUp(() {
    store = _PreviewStore();
    Get.put<ReceiptStore>(store);
  });

  tearDown(Get.reset);

  Future<void> pumpPreview(WidgetTester tester, Transaction tx) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ReceiptPreview(transaction: tx))),
    );
    await tester.pump();
  }

  testWidgets('offline without a local copy says it will show online', (
    WidgetTester tester,
  ) async {
    store.linkError = const NetworkFailure();
    await pumpPreview(tester, _tx(attachmentUrl: 'user-1/tx-1'));

    expect(find.text('Receipt will show when you are online'), findsOneWidget);
  });

  testWidgets('a pending photo says it is waiting to upload', (
    WidgetTester tester,
  ) async {
    store
      ..local = Uint8List.fromList(<int>[1, 2, 3])
      ..pending = true;
    await pumpPreview(tester, _tx());

    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('Waiting to upload'), findsOneWidget);
    expect(store.signedLinkCalls, 0, reason: 'the local copy is enough');
  });

  testWidgets('another failure offers a retry', (WidgetTester tester) async {
    store.linkError = const DatabaseFailure();
    await pumpPreview(tester, _tx(attachmentUrl: 'user-1/tx-1'));
    expect(find.text('Retry'), findsOneWidget);

    store.linkError = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(store.signedLinkCalls, 2);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('an edited transaction shows its new receipt', (
    WidgetTester tester,
  ) async {
    store.local = Uint8List.fromList(<int>[1]);
    await pumpPreview(tester, _tx());
    expect(_shown(tester), <int>[1]);

    store.local = Uint8List.fromList(<int>[2]);
    await pumpPreview(tester, _tx(updatedAt: DateTime(2026, 10, 22)));
    expect(_shown(tester), <int>[2]);
  });

  testWidgets('a receipt image that fails to load offers a retry', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester, _tx(attachmentUrl: 'user-1/tx-1'));
    // Widget tests answer every HTTP request with an error.
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(store.signedLinkCalls, 2);
  });

  testWidgets('the form shows the saved photo as it is now', (
    WidgetTester tester,
  ) async {
    store.local = Uint8List.fromList(<int>[3]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReceiptField(
            existingPath: 'user-1/tx-1',
            transactionId: 'tx-1',
            onPicked: (_) {},
            onRemoved: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Receipt photo'), findsOneWidget);
    expect(_shown(tester), <int>[3]);
  });

  testWidgets('a transaction without a receipt shows nothing', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester, _tx());

    expect(find.text('Receipt'), findsNothing);
    expect(store.signedLinkCalls, 0);
  });
}
