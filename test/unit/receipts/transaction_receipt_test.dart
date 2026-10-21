import 'dart:io';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/avatar_rules.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fake_receipts.dart';

void main() {
  late Directory root;
  late FakeFinance finance;
  late FakeReceiptStore receipts;
  late TransactionController controller;
  final Uint8List photo = Uint8List.fromList(List<int>.filled(64, 7));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('receipt_tx_test');
    finance = FakeFinance()..addAccount('Cash', '0');
    receipts = FakeReceiptStore(finance.repositories.transactions, root);
    controller = TransactionController(
      finance.repositories.transactions,
      finance.repositories.accounts,
      finance.repositories.categories,
      DataChangeNotifier(),
      receipts: receipts,
    );
  });

  tearDown(() => root.delete(recursive: true));

  Future<bool> save({
    Transaction? existing,
    ({Uint8List bytes, String fileName})? newReceipt,
    bool removeReceipt = false,
  }) => controller.saveTransaction(
    id: existing?.id ?? 'tx-9',
    existing: existing,
    type: TransactionType.expense,
    amount: Decimal.parse('120'),
    accountId: 'acc-1',
    categoryId: null,
    date: DateTime(2026, 10, 21),
    note: 'Dinner',
    newReceipt: newReceipt,
    removeReceipt: removeReceipt,
  );

  test('saving with a new photo stages it for the transaction', () async {
    expect(await save(newReceipt: (bytes: photo, fileName: 'r.jpg')), isTrue);

    expect(finance.transactions.single.id, 'tx-9');
    expect(await receipts.isPending('tx-9'), isTrue);
  });

  test('removing the receipt clears it and marks the file removed', () async {
    final Transaction stored = finance.addTransaction(
      id: 'tx-1',
      type: TransactionType.expense,
      amount: '50',
      attachmentUrl: 'user-1/tx-1',
    );

    expect(await save(existing: stored, removeReceipt: true), isTrue);
    expect(finance.transactions.single.attachmentUrl, isNull);
    expect(receipts.markedRemoved, <String>['tx-1']);
  });

  test('an edit from a form opened before the photo was linked keeps it', () async {
    final Transaction opened = finance.addTransaction(
      id: 'tx-1',
      type: TransactionType.expense,
      amount: '50',
    );
    // A sync links the photo while the form is open.
    finance.transactions[0] = opened.copyWith(attachmentUrl: 'user-1/tx-1');

    expect(await save(existing: opened), isTrue);
    expect(finance.transactions.single.attachmentUrl, 'user-1/tx-1');
  });

  test('deleting a transaction with a receipt removes the receipt', () async {
    finance.addTransaction(
      id: 'tx-1',
      type: TransactionType.expense,
      amount: '50',
      attachmentUrl: 'user-1/tx-1',
    );

    expect(await controller.deleteTransaction('tx-1'), isTrue);
    expect(receipts.markedRemoved, <String>['tx-1']);
  });

  test(
    'deleting a transaction without a receipt leaves storage alone',
    () async {
      finance.addTransaction(
        id: 'tx-2',
        type: TransactionType.expense,
        amount: '5',
      );

      expect(await controller.deleteTransaction('tx-2'), isTrue);
      expect(receipts.markedRemoved, isEmpty);
    },
  );

  test('an invalid photo fails the save before anything is written', () async {
    expect(await save(newReceipt: (bytes: photo, fileName: 'x.gif')), isFalse);

    expect(controller.save.error.value, AvatarProblem.unsupportedType.message);
    expect(finance.transactions, isEmpty);
    expect(await receipts.localFile('tx-9'), isNull);
  });
}
