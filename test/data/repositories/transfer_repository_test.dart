import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

TransferLegs _legs({
  String transferId = 'tr-1',
  String from = 'acc-cash',
  String to = 'acc-bank',
  String amount = '300',
}) => TransferLegs.build(
  transferId: transferId,
  outgoingId: '$transferId-out',
  incomingId: '$transferId-in',
  fromAccountId: from,
  toAccountId: to,
  amount: Decimal.parse(amount),
  date: DateTime(2026, 10, 14, 12),
  now: DateTime(2026, 10, 14, 12),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TransactionRepository repo;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repo = TransactionRepository(
      SupabaseClient('https://dummy.supabase.co', 'dummy-anon-key'),
      database: database,
      syncEngine: SyncEngine(database: database),
    );
  });

  tearDown(() => database.close());

  Future<List<SyncQueueItem>> queue() => database.getPendingQueue();

  test('a transfer is stored and queued as both legs, outgoing first', () async {
    await repo.createTransfer(_legs());

    final TransferLegs? stored = await repo.getTransfer('tr-1');
    expect(stored?.fromAccountId, 'acc-cash');
    expect(stored?.toAccountId, 'acc-bank');
    expect(stored?.amount, Decimal.parse('300'));

    final List<SyncQueueItem> items = await queue();
    expect(
      items.map((SyncQueueItem i) => (i.operation, i.entityId)).toList(),
      <(SyncOperation, String)>[
        (SyncOperation.create, 'tr-1-out'),
        (SyncOperation.create, 'tr-1-in'),
      ],
    );
    expect(items.first.payload['transfer_id'], 'tr-1');
  });

  test('a retried create does not duplicate the legs', () async {
    await repo.createTransfer(_legs());
    await repo.createTransfer(_legs());

    final List<Transaction> rows = await repo.getTransactions();
    expect(rows.where((Transaction t) => t.transferId == 'tr-1').length, 2);
  });

  test('an edit updates both legs and queues the outgoing one first', () async {
    await repo.createTransfer(_legs());
    final int before = (await queue()).length;

    await repo.updateTransfer(_legs(amount: '450'));

    expect((await repo.getTransfer('tr-1'))?.amount, Decimal.parse('450'));
    final List<SyncQueueItem> updates = (await queue()).skip(before).toList();
    expect(
      updates.map((SyncQueueItem i) => (i.operation, i.entityId)).toList(),
      <(SyncOperation, String)>[
        (SyncOperation.update, 'tr-1-out'),
        (SyncOperation.update, 'tr-1-in'),
      ],
    );
  });

  test('deleting a transfer removes both legs together', () async {
    await repo.createTransfer(_legs());
    final int before = (await queue()).length;

    await repo.deleteTransfer('tr-1');

    expect(await repo.getTransfer('tr-1'), isNull);
    expect(await repo.getTransactions(), isEmpty);
    final List<SyncQueueItem> deletes = (await queue()).skip(before).toList();
    expect(
      deletes.map((SyncQueueItem i) => i.operation).toSet(),
      <SyncOperation>{SyncOperation.delete},
    );
    expect(
      deletes.map((SyncQueueItem i) => i.entityId).toSet(),
      <String>{'tr-1-out', 'tr-1-in'},
    );
  });

  test('replacing a transfer retires the old legs in the same step', () async {
    await repo.createTransfer(_legs());

    // The accounts swapped, so the edit is recorded as a new transfer.
    await repo.createTransfer(
      _legs(transferId: 'tr-2', from: 'acc-bank', to: 'acc-cash'),
      replacing: 'tr-1',
    );

    expect(await repo.getTransfer('tr-1'), isNull);
    final TransferLegs? replaced = await repo.getTransfer('tr-2');
    expect(replaced?.fromAccountId, 'acc-bank');
    expect(replaced?.toAccountId, 'acc-cash');
    expect((await repo.getTransactions()).length, 2);
  });
}
