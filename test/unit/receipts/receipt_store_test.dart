import 'dart:io';
import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/avatar_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fake_receipts.dart';

Uint8List _bytes(int length) => Uint8List(length)..fillRange(0, length, 7);

void main() {
  late Directory root;
  late FakeFinance finance;
  late FakeReceiptStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('receipts_test');
    finance = FakeFinance()..addAccount('Cash', '0');
    finance.addTransaction(
      id: 'tx-1',
      type: TransactionType.expense,
      amount: '50',
    );
    store = FakeReceiptStore(finance.repositories.transactions, root);
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'a staged photo uploads once and is linked to its transaction',
    () async {
      await store.stage('tx-1', _bytes(10), 'IMG_1.jpg');
      expect(await store.isPending('tx-1'), isTrue);

      await store.uploadPending();
      expect(store.puts, <String>['user-1/tx-1']);
      expect(store.contentTypes.single, 'image/jpeg');
      expect(finance.transactions.single.attachmentUrl, 'user-1/tx-1');
      expect(await store.isPending('tx-1'), isFalse);
      expect(await store.localFile('tx-1'), isNotNull, reason: 'kept as cache');

      await store.uploadPending();
      expect(store.puts, hasLength(1), reason: 'nothing left to send');
    },
  );

  test('a failed upload keeps the photo pending', () async {
    await store.stage('tx-1', _bytes(10), 'a.jpg');
    store.failNextPut = true;

    await expectLater(store.uploadPending(), throwsA(isA<NetworkFailure>()));
    expect(await store.isPending('tx-1'), isTrue);
    expect(finance.transactions.single.attachmentUrl, isNull);
  });

  test('an invalid photo is refused with the rule message', () async {
    await expectLater(
      store.stage('tx-1', _bytes(10), 'scan.pdf'),
      throwsA(
        isA<StorageFailure>().having(
          (StorageFailure e) => e.message,
          'message',
          AvatarProblem.unsupportedType.message,
        ),
      ),
    );
    expect(await store.localFile('tx-1'), isNull);
  });

  test('a removed receipt is not uploaded and its file is deleted', () async {
    await store.stage('tx-1', _bytes(10), 'a.jpg');
    await store.markRemoved('tx-1');
    expect(await store.localFile('tx-1'), isNull);

    await store.uploadPending();
    expect(store.puts, isEmpty);
    expect(store.removed, <String>['user-1/tx-1']);

    await store.uploadPending();
    expect(store.removed, hasLength(1), reason: 'marker dropped');
  });

  test('staging again replaces the earlier photo', () async {
    await store.stage('tx-1', _bytes(10), 'a.jpg');
    await store.stage('tx-1', _bytes(20), 'b.png');

    await store.uploadPending();
    expect(store.puts, <String>['user-1/tx-1']);
    expect(store.contentTypes.single, 'image/png');
  });

  test("only the signed-in user's photos are uploaded", () async {
    await store.stage('tx-1', _bytes(10), 'a.jpg');
    store.currentUserId = 'user-2';

    await store.uploadPending();
    expect(store.puts, isEmpty);
    expect(await store.localFile('tx-1'), isNull);
  });

  test('staging or removing a receipt asks for a sync', () async {
    int queued = 0;
    store.onQueued = () => queued++;

    await store.stage('tx-1', _bytes(10), 'a.jpg');
    expect(queued, 1);
    await store.markRemoved('tx-1');
    expect(queued, 2);
  });

  test('waiting photos are counted, removals are not', () async {
    await store.stage('tx-1', _bytes(10), 'a.jpg');
    await store.stage('tx-2', _bytes(10), 'b.png');
    await store.markRemoved('tx-3');

    expect(await store.pendingPhotoCount(), 2);
  });

  test('a photo changed during its upload is sent again', () async {
    await store.stage('tx-1', _bytes(10), 'a.jpg');
    store.onPut = () async {
      store.onPut = null;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.stage('tx-1', _bytes(20), 'b.jpg');
    };

    await store.uploadPending();
    expect(await store.isPending('tx-1'), isTrue, reason: 'new bytes wait');

    await store.uploadPending();
    expect(store.putSizes, <int>[10, 20]);
    expect(await store.isPending('tx-1'), isFalse);
  });

  test('a broken photo does not stop the others', () async {
    finance.addTransaction(id: 'tx-2', type: TransactionType.expense, amount: '9');
    await store.stage('tx-1', _bytes(10), 'a.jpg');
    await store.stage('tx-2', _bytes(10), 'b.jpg');
    store.brokenPath = 'user-1/tx-1';

    await store.uploadPending();
    expect(store.puts, <String>['user-1/tx-2']);
    expect(await store.isPending('tx-1'), isTrue);
  });

  test('deleteAll removes every stored receipt and the local folder', () async {
    store.listed = <String>['user-1/tx-1', 'user-1/tx-2'];
    await store.stage('tx-1', _bytes(10), 'a.jpg');

    await store.deleteAll();
    expect(store.removed, <String>['user-1/tx-1', 'user-1/tx-2']);
    expect(await store.localFile('tx-1'), isNull);
  });
}
