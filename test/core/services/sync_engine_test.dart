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

  test('receipt photos waiting to upload count as unsynced', () async {
    syncEngine.pendingFiles = () async => 2;
    await syncEngine.refreshQueueStats();
    expect(syncEngine.pendingCount.value, 2);
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

  group('local data belongs to one user', () {
    Future<void> seedFor(String userId) async {
      await database.db.insert('accounts', <String, Object?>{
        'id': 'acc-$userId',
        'user_id': userId,
        'name': 'Cash',
        'type': 'cash',
        'opening_balance': '0',
        'opening_balance_date': '2026-01-01',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      await database.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'accounts',
          entityId: 'acc-$userId',
          payload: <String, dynamic>{'name': 'Cash'},
          createdAt: DateTime.now(),
        ),
      );
      await database.setMetadata('cursor_accounts_$userId', '2026-01-01');
    }

    Future<int> count(String table) async =>
        (await database.db.query(table)).length;

    test('the first user to sync keeps what is on the device', () async {
      await seedFor('user-a');
      await syncEngine.claimLocalData('user-a');
      expect(await count('accounts'), 1);
      expect(await database.getPendingQueueCount(), 1);
      expect(await database.getMetadata(AppDatabase.localOwnerKey), 'user-a');
    });

    test('the split tables are cleared for another user', () async {
      await seedFor('user-a');
      const String now = '2026-10-26T00:00:00Z';
      await database.db.insert('split_groups', <String, Object?>{
        'id': 'sg1',
        'user_id': 'user-a',
        'name': 'Goa',
        'created_at': now,
        'updated_at': now,
      });
      await database.db.insert('split_group_members', <String, Object?>{
        'id': 'sm1',
        'user_id': 'user-a',
        'group_id': 'sg1',
        'contact_id': null,
        'created_at': now,
        'updated_at': now,
      });
      await database.db.insert('split_expenses', <String, Object?>{
        'id': 'se1',
        'user_id': 'user-a',
        'group_id': 'sg1',
        'title': 'Dinner',
        'total_amount': '1200',
        'expense_date': now,
        'split_mode': 'equal',
        'created_at': now,
        'updated_at': now,
      });
      await database.db.insert('split_expense_parts', <String, Object?>{
        'id': 'sp1',
        'user_id': 'user-a',
        'split_expense_id': 'se1',
        'member_id': 'sm1',
        'paid_amount': '800',
        'share_amount': '300',
        'created_at': now,
        'updated_at': now,
      });
      await database.db.insert('split_settlements', <String, Object?>{
        'id': 'ss1',
        'user_id': 'user-a',
        'group_id': 'sg1',
        'from_member_id': 'sm1',
        'to_member_id': 'sm1',
        'amount': '200',
        'settled_at': now,
        'created_at': now,
        'updated_at': now,
      });

      await syncEngine.claimLocalData('user-a');
      await syncEngine.claimLocalData('user-b');

      for (final String table in <String>[
        'split_groups',
        'split_group_members',
        'split_expenses',
        'split_expense_parts',
        'split_settlements',
      ]) {
        expect(await count(table), 0, reason: '$table is wiped for user-b');
      }
    });

    test(
      "another user never gets the previous user's rows or uploads",
      () async {
        await seedFor('user-a');
        await syncEngine.claimLocalData('user-a');

        await syncEngine.claimLocalData('user-b');

        expect(await count('accounts'), 0);
        expect(await database.getPendingQueueCount(), 0);
        expect(await database.getMetadata('cursor_accounts_user-a'), isNull);
        expect(await database.getMetadata(AppDatabase.localOwnerKey), 'user-b');
        // System categories are shared and survive.
        expect(
          await database.db.query('categories', where: 'is_system = 1'),
          isNotEmpty,
        );
      },
    );
  });
}
