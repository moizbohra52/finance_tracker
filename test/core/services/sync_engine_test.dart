import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SyncEngine syncEngine;

  setUp(() async {
    database = await AppDatabase.inMemory();
    syncEngine = SyncEngine(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('SyncEngine initializes with zero pending items', () async {
    await syncEngine.refreshQueueStats();
    expect(syncEngine.pendingCount.value, equals(0));
    expect(syncEngine.state.value, equals(SyncState.synced));
  });

  test(
    'SyncEngine detects pending items and updates state to waiting',
    () async {
      await database.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'transactions',
          entityId: 'tx-offline-1',
          payload: <String, dynamic>{'amount': '500.00'},
          createdAt: DateTime.now(),
        ),
      );

      await syncEngine.refreshQueueStats();
      expect(syncEngine.pendingCount.value, equals(1));
      expect(syncEngine.state.value, equals(SyncState.waiting));

      final List<SyncQueueItem> items = await syncEngine.getPendingItems();
      expect(items.length, equals(1));
      expect(items.first.entityId, equals('tx-offline-1'));
    },
  );

  test('SyncEngine retryFailed resets failed items to pending', () async {
    final int id = await database.enqueue(
      SyncQueueItem(
        operation: SyncOperation.create,
        entity: 'transactions',
        entityId: 'tx-failed-1',
        payload: <String, dynamic>{'amount': '250.00'},
        createdAt: DateTime.now(),
        status: SyncItemStatus.failed,
        retryCount: 5,
        errorMessage: 'Temporary network failure',
      ),
    );

    await syncEngine.refreshQueueStats();
    expect(syncEngine.failedCount.value, equals(1));
    expect(syncEngine.state.value, equals(SyncState.error));

    await syncEngine.retryFailed();
    await syncEngine.refreshQueueStats();

    final List<Map<String, dynamic>> rows = await database.db.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
    expect(rows.first['status'], equals('pending'));
    expect(rows.first['retry_count'], equals(0));
    expect(rows.first['error_message'], isNull);
  });

  test(
    'SyncEngine sets state to offline when connectivity reports offline',
    () async {
      final ConnectivityService connectivity = ConnectivityService.forTest(
        watch: () => Stream<NetworkStatus>.fromIterable(<NetworkStatus>[
          NetworkStatus.offline,
        ]),
        check: () async => NetworkStatus.offline,
      );
      connectivity.onInit();

      final SyncEngine engineWithConn = SyncEngine(
        database: database,
        connectivity: connectivity,
      );
      engineWithConn.onInit();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(engineWithConn.state.value, equals(SyncState.offline));
    },
  );

  test(
    'Pending items survive database close and re-open (app restart)',
    () async {
      await database.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'accounts',
          entityId: 'acc-restart-1',
          payload: <String, dynamic>{'name': 'Cash in Wallet'},
          createdAt: DateTime.now(),
        ),
      );

      expect(await database.getPendingQueueCount(), equals(1));

      // Simulate app closing and reopening with new database instance
      final AppDatabase newDbInstance = AppDatabase(database: database.db);
      final SyncEngine newEngine = SyncEngine(database: newDbInstance);
      await newEngine.refreshQueueStats();

      expect(newEngine.pendingCount.value, equals(1));
      final List<SyncQueueItem> items = await newEngine.getPendingItems();
      expect(items.first.entityId, equals('acc-restart-1'));
    },
  );
}
