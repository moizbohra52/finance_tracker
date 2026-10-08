import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = await AppDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  test('AppDatabase creates tables and seeds system categories', () async {
    final List<Map<String, dynamic>> categories = await database.db.query(
      'categories',
    );
    expect(categories.length, equals(25));
    expect(
      categories.any((c) => c['name'] == 'Salary' && c['is_system'] == 1),
      isTrue,
    );
    expect(
      categories.any(
        (c) => c['name'] == 'Food & Dining' && c['is_system'] == 1,
      ),
      isTrue,
    );
  });

  test('Sync queue enqueue, fetch pending, update status and clear', () async {
    final SyncQueueItem item1 = SyncQueueItem(
      operation: SyncOperation.create,
      entity: 'transactions',
      entityId: 'tx-123',
      payload: <String, dynamic>{'amount': '100.00', 'type': 'income'},
      createdAt: DateTime.now(),
    );

    final int id = await database.enqueue(item1);
    expect(id, isPositive);

    final int count = await database.getPendingQueueCount();
    expect(count, equals(1));

    final List<SyncQueueItem> pending = await database.getPendingQueue();
    expect(pending.length, equals(1));
    expect(pending.first.entityId, equals('tx-123'));
    expect(pending.first.status, equals(SyncItemStatus.pending));

    await database.updateQueueItemStatus(id: id, status: SyncItemStatus.synced);

    final int updatedCount = await database.getPendingQueueCount();
    expect(updatedCount, equals(0));

    await database.clearSyncedQueueItems();
    final List<Map<String, dynamic>> remaining = await database.db.query(
      'sync_queue',
    );
    expect(remaining, isEmpty);
  });

  test('Metadata get and set', () async {
    expect(await database.getMetadata('last_pulled_tx'), isNull);

    await database.setMetadata('last_pulled_tx', '2026-10-08T12:00:00Z');
    expect(
      await database.getMetadata('last_pulled_tx'),
      equals('2026-10-08T12:00:00Z'),
    );

    // Overwrite works
    await database.setMetadata('last_pulled_tx', '2026-10-08T13:00:00Z');
    expect(
      await database.getMetadata('last_pulled_tx'),
      equals('2026-10-08T13:00:00Z'),
    );
  });
}
