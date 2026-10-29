import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('a new database has the UPI ID column', () async {
    final List<Map<String, Object?>> columns = await database.db.rawQuery(
      'PRAGMA table_info(user_settings)',
    );
    expect(columns.map((c) => c['name']), contains('upi_id'));
  });

  test('upgrading a version 1 file adds the UPI ID column', () async {
    final Database old = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        // Not the database setUp opened, which is already at the new version.
        singleInstance: false,
        onCreate: (Database db, int _) => db.execute(
          'CREATE TABLE user_settings (id TEXT PRIMARY KEY, date_format TEXT)',
        ),
      ),
    );
    await old.insert('user_settings', <String, Object?>{'id': 'u'});

    await AppDatabase.upgrade(old, 1, AppDatabase.databaseVersion);

    final List<Map<String, Object?>> rows = await old.query('user_settings');
    expect(rows.single['id'], 'u', reason: 'existing rows are kept');
    expect(rows.single.containsKey('upi_id'), isTrue);
    await old.close();
  });

  test(
    'upgrading a version 3 file adds the savings contributions table',
    () async {
      final Database old = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 3, singleInstance: false),
      );

      await AppDatabase.upgrade(old, 3, AppDatabase.databaseVersion);

      final List<Map<String, Object?>> columns = await old.rawQuery(
        'PRAGMA table_info(savings_contributions)',
      );
      expect(
        columns.map((Map<String, Object?> c) => c['name']),
        containsAll(<String>['goal_id', 'transaction_id']),
      );
      await old.close();
    },
  );

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

  test(
    'upgrading a version 4 file adds the split tables and link columns',
    () async {
      final Database old = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 4,
          // Not the database setUp opened, which is already at the new version.
          singleInstance: false,
          onCreate: (Database db, int _) async {
            await db.execute('''
              CREATE TABLE transactions (
                id TEXT PRIMARY KEY,
                user_id TEXT,
                account_id TEXT NOT NULL,
                type TEXT NOT NULL,
                amount TEXT NOT NULL,
                transaction_date TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE contact_transactions (
                id TEXT PRIMARY KEY,
                user_id TEXT,
                contact_id TEXT NOT NULL,
                type TEXT NOT NULL,
                amount TEXT NOT NULL,
                transaction_date TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
          },
        ),
      );
      await old.insert('transactions', <String, Object?>{
        'id': 't1',
        'account_id': 'a1',
        'type': 'expense',
        'amount': '100',
        'transaction_date': '2026-10-01',
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      });
      await old.insert('contact_transactions', <String, Object?>{
        'id': 'ct1',
        'contact_id': 'c1',
        'type': 'credit',
        'amount': '100',
        'transaction_date': '2026-10-01',
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      });

      await AppDatabase.upgrade(old, 4, AppDatabase.databaseVersion);

      for (final String table in <String>[
        'split_groups',
        'split_group_members',
        'split_expenses',
        'split_expense_parts',
        'split_settlements',
      ]) {
        final List<Map<String, Object?>> columns = await old.rawQuery(
          'PRAGMA table_info($table)',
        );
        expect(columns, isNotEmpty, reason: '$table is created by the upgrade');
      }
      for (final String table in <String>[
        'transactions',
        'contact_transactions',
      ]) {
        final List<Map<String, Object?>> columns = await old.rawQuery(
          'PRAGMA table_info($table)',
        );
        expect(
          columns.map((Map<String, Object?> c) => c['name']),
          containsAll(<String>['split_expense_id', 'split_settlement_id']),
          reason: '$table gains the link columns',
        );
      }
      final List<Map<String, Object?>> transactions = await old.query(
        'transactions',
      );
      expect(transactions.single['id'], 't1', reason: 'existing rows are kept');
      await old.close();
    },
  );

  test('a fresh database has the split tables and link columns', () async {
    for (final String table in <String>[
      'split_groups',
      'split_group_members',
      'split_expenses',
      'split_expense_parts',
      'split_settlements',
    ]) {
      final List<Map<String, Object?>> columns = await database.db.rawQuery(
        'PRAGMA table_info($table)',
      );
      expect(columns, isNotEmpty, reason: '$table exists on a fresh database');
    }
    for (final String table in <String>[
      'transactions',
      'contact_transactions',
    ]) {
      final List<Map<String, Object?>> columns = await database.db.rawQuery(
        'PRAGMA table_info($table)',
      );
      expect(
        columns.map((Map<String, Object?> c) => c['name']),
        containsAll(<String>['split_expense_id', 'split_settlement_id']),
      );
    }
  });
}
