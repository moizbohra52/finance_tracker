import 'dart:convert';
import 'package:finance_tracker/core/services/backup_service.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const BackupService service = BackupService();
  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('Backup Creation', () {
    test('creates valid JSON backup and excludes sensitive fields', () async {
      // Seed some test data
      await db.db.insert('accounts', <String, dynamic>{
        'id': 'acc-1',
        'user_id': 'user-1',
        'name': 'HDFC Bank',
        'type': 'bank',
        'opening_balance': '50000.00',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 'synced',
      });

      await db.db.insert('transactions', <String, dynamic>{
        'id': 'tx-1',
        'user_id': 'user-1',
        'account_id': 'acc-1',
        'type': 'income',
        'amount': '75000.00',
        'transaction_date': DateTime.now().toIso8601String(),
        'note': 'Salary',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 'synced',
      });

      final Map<String, dynamic> backup = await service.createBackup(
        db,
        userId: 'user-1',
      );

      expect(backup['version'], 1);
      expect(backup['app'], 'finance_tracker');
      expect(backup['created_at'], isNotNull);
      expect(backup['data'], isNotNull);

      final Map<String, dynamic> data = backup['data'] as Map<String, dynamic>;
      final List<dynamic> accounts = data['accounts'] as List<dynamic>;
      expect(accounts.length, 1);
      final Map<String, dynamic> firstAccount =
          accounts.first as Map<String, dynamic>;
      expect(firstAccount['name'], 'HDFC Bank');

      final List<dynamic> txs = data['transactions'] as List<dynamic>;
      expect(txs.length, 1);
      final Map<String, dynamic> firstTx = txs.first as Map<String, dynamic>;
      expect(firstTx['amount'], '75000.00');

      // Check no sensitive keys
      final String jsonStr = jsonEncode(backup);
      expect(jsonStr.contains('password'), isFalse);
      expect(jsonStr.contains('access_token'), isFalse);
      expect(jsonStr.contains('refresh_token'), isFalse);
    });
  });

  group('Backup Validation', () {
    test('rejects empty string', () {
      final BackupValidationResult result = service.validateBackup('');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('empty'));
    });

    test('rejects malformed JSON', () {
      final BackupValidationResult result = service.validateBackup(
        '{ invalid json: 123',
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('not a valid JSON'));
    });

    test('rejects missing or incompatible version', () {
      final BackupValidationResult noVer = service.validateBackup(
        '{"data": {}}',
      );
      expect(noVer.isValid, isFalse);
      expect(noVer.errorMessage, contains('version'));

      final BackupValidationResult futureVer = service.validateBackup(
        '{"version": 999, "data": {}}',
      );
      expect(futureVer.isValid, isFalse);
      expect(futureVer.errorMessage, contains('newer than supported'));
    });

    test('rejects missing data section or empty records', () {
      final BackupValidationResult noData = service.validateBackup(
        '{"version": 1, "app": "finance_tracker"}',
      );
      expect(noData.isValid, isFalse);
      expect(noData.errorMessage, contains('"data" section'));

      final BackupValidationResult emptyRecords = service.validateBackup(
        '{"version": 1, "data": {"accounts": []}}',
      );
      expect(emptyRecords.isValid, isFalse);
      expect(
        emptyRecords.errorMessage,
        contains('does not contain any records'),
      );
    });

    test('accepts valid backup and returns record statistics', () {
      final Map<String, dynamic> validPayload = <String, dynamic>{
        'version': 1,
        'app': 'finance_tracker',
        'created_at': DateTime(2026, 10, 9).toIso8601String(),
        'data': <String, dynamic>{
          'accounts': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'acc-1',
              'name': 'Cash',
              'type': 'cash',
              'opening_balance': '100',
              'is_active': 1,
              'created_at': '2026-01-01',
              'updated_at': '2026-01-01',
            },
          ],
          'transactions': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'tx-1',
              'account_id': 'acc-1',
              'type': 'expense',
              'amount': '50',
              'transaction_date': '2026-01-02',
              'created_at': '2026-01-02',
              'updated_at': '2026-01-02',
            },
            <String, dynamic>{
              'id': 'tx-2',
              'account_id': 'acc-1',
              'type': 'income',
              'amount': '200',
              'transaction_date': '2026-01-03',
              'created_at': '2026-01-03',
              'updated_at': '2026-01-03',
            },
          ],
        },
      };

      final BackupValidationResult result = service.validateBackup(
        jsonEncode(validPayload),
      );
      expect(result.isValid, isTrue);
      expect(result.totalRecords, 3);
      expect(result.tableCounts['accounts'], 1);
      expect(result.tableCounts['transactions'], 2);
    });
  });

  group('Backup Restore', () {
    test('restores in merge mode without deleting other records', () async {
      // 1. Existing local record
      await db.db.insert('accounts', <String, dynamic>{
        'id': 'existing-acc',
        'user_id': 'user-1',
        'name': 'Existing Account',
        'type': 'bank',
        'opening_balance': '1000.00',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 'synced',
      });

      // 2. Backup data with one new account and one updated account
      final Map<String, List<Map<String, dynamic>>> backupData =
          <String, List<Map<String, dynamic>>>{
            'accounts': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'new-acc',
                'user_id': 'user-1',
                'name': 'New Account',
                'type': 'cash',
                'opening_balance': '500.00',
                'is_active': 1,
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
                'sync_status': 'synced',
              },
            ],
          };

      final RestoreResult result = await service.restoreBackup(
        db,
        backupData,
        replaceExisting: false,
        userId: 'user-1',
      );

      expect(result.success, isTrue);
      expect(result.totalRestored, 1);

      // Verify both accounts exist in DB
      final List<Map<String, dynamic>> rows = await db.db.query('accounts');
      expect(rows.length, 2);
      expect(rows.any((r) => r['id'] == 'existing-acc'), isTrue);
      expect(rows.any((r) => r['id'] == 'new-acc'), isTrue);
    });

    test('restores in clean replace mode wiping old records first', () async {
      // 1. Existing local records
      await db.db.insert('accounts', <String, dynamic>{
        'id': 'old-acc',
        'user_id': 'user-1',
        'name': 'Old Account',
        'type': 'bank',
        'opening_balance': '1000.00',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 'synced',
      });

      // 2. Backup data to replace
      final Map<String, List<Map<String, dynamic>>> backupData =
          <String, List<Map<String, dynamic>>>{
            'accounts': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'backup-acc',
                'user_id': 'user-1',
                'name': 'Restored Account',
                'type': 'cash',
                'opening_balance': '2000.00',
                'is_active': 1,
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
                'sync_status': 'synced',
              },
            ],
          };

      final RestoreResult result = await service.restoreBackup(
        db,
        backupData,
        replaceExisting: true,
        userId: 'user-1',
      );

      expect(result.success, isTrue);

      // Verify old account was removed and restored account is present
      final List<Map<String, dynamic>> rows = await db.db.query('accounts');
      expect(rows.length, 1);
      expect(rows.first['id'], 'backup-acc');
      expect(rows.first['name'], 'Restored Account');
    });

    test(
      'handles duplicate IDs gracefully by replacing/updating them',
      () async {
        await db.db.insert('accounts', <String, dynamic>{
          'id': 'same-id',
          'user_id': 'user-1',
          'name': 'Old Name',
          'type': 'cash',
          'opening_balance': '100.00',
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'sync_status': 'synced',
        });

        final Map<String, List<Map<String, dynamic>>> backupData =
            <String, List<Map<String, dynamic>>>{
              'accounts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'same-id',
                  'user_id': 'user-1',
                  'name': 'Updated Name From Backup',
                  'type': 'cash',
                  'opening_balance': '999.00',
                  'is_active': 1,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                  'sync_status': 'synced',
                },
              ],
            };

        final RestoreResult result = await service.restoreBackup(
          db,
          backupData,
          replaceExisting: false,
        );

        expect(result.success, isTrue);

        final List<Map<String, dynamic>> rows = await db.db.query(
          'accounts',
          where: 'id = ?',
          whereArgs: <Object>['same-id'],
        );
        expect(rows.length, 1);
        expect(rows.first['name'], 'Updated Name From Backup');
        expect(rows.first['opening_balance'], '999.00');
      },
    );

    test(
      'merge queues entries parents first and applies settings and profile',
      () async {
        final String now = DateTime.now().toIso8601String();
        await db.db.insert('profiles', <String, dynamic>{
          'id': 'user-2',
          'full_name': 'Current Name',
          'avatar_url': 'user-2/avatar.jpg',
          'currency_code': 'INR',
        });
        await db.db.insert('user_settings', <String, dynamic>{
          'id': 'server-row-id',
          'user_id': 'user-2',
          'date_format': 'dd/MM/yyyy',
          'first_day_of_week': 'monday',
          'language_code': 'en',
        });

        final Map<String, List<Map<String, dynamic>>> backupData =
            <String, List<Map<String, dynamic>>>{
              'transactions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'tx-1',
                  'user_id': 'user-1',
                  'account_id': 'acc-1',
                  'type': 'expense',
                  'amount': '10.00',
                  'transaction_date': now,
                  'created_at': now,
                  'updated_at': now,
                  'deleted_at': now,
                  'sync_status': 'synced',
                },
              ],
              'accounts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'acc-1',
                  'user_id': 'user-1',
                  'name': 'Cash',
                  'type': 'cash',
                  'opening_balance': '0',
                  'is_active': 1,
                  'created_at': now,
                  'updated_at': now,
                  'sync_status': 'synced',
                },
              ],
              'categories': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'sys-cat',
                  'name': 'Food',
                  'type': 'expense',
                  'icon': 'food',
                  'is_system': 1,
                  'created_at': now,
                  'updated_at': now,
                },
              ],
              'user_settings': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'old-row-id',
                  'user_id': 'user-1',
                  'date_format': 'yyyy-MM-dd',
                  'number_format': 'indian',
                  'first_day_of_week': null,
                  'language_code': 'en',
                  'default_account_id': 'acc-1',
                  'notifications_enabled': 1,
                  'sync_status': 'synced',
                },
              ],
              'profiles': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'user-1',
                  'full_name': 'Restored Name',
                  'mobile': null,
                  'avatar_url': 'user-1/old.jpg',
                  'currency_code': null,
                  'timezone': 'Asia/Kolkata',
                  'sync_status': 'synced',
                },
              ],
            };

        final RestoreResult result = await service.restoreBackup(
          db,
          backupData,
          replaceExisting: false,
          userId: 'user-2',
        );
        expect(result.success, isTrue);

        final List<SyncQueueItem> queue = await db.getPendingQueue();
        expect(
          queue.map(
            (SyncQueueItem q) =>
                '${q.operation.name}:${q.entity}:${q.entityId}',
          ),
          <String>[
            'create:accounts:acc-1',
            'create:transactions:tx-1',
            'update:user_settings:user-2',
            'update:profiles:user-2',
          ],
        );

        // The upload restores the tombstone and runs as the signed-in user.
        final Map<String, dynamic> txPayload = queue[1].payload;
        expect(txPayload['__restore'], isTrue);
        expect(txPayload['deleted_at'], now);
        expect(txPayload['user_id'], 'user-2');

        // Only editable columns; a null the server rejects is left out.
        expect(queue[2].payload, <String, dynamic>{
          'date_format': 'yyyy-MM-dd',
          'number_format': 'indian',
          'language_code': 'en',
          'default_account_id': 'acc-1',
        });
        // The avatar is not in the backup (only its path), so it stays.
        expect(queue[3].payload, <String, dynamic>{
          'full_name': 'Restored Name',
          'mobile': null,
          'timezone': 'Asia/Kolkata',
        });

        final Map<String, dynamic> tx = (await db.db.query(
          'transactions',
        )).single;
        expect(tx['user_id'], 'user-2');
        expect(tx['sync_status'], 'pending');

        final Map<String, dynamic> settings = (await db.db.query(
          'user_settings',
        )).single;
        expect(settings['user_id'], 'user-2');
        expect(settings['date_format'], 'yyyy-MM-dd');
        expect(settings['first_day_of_week'], 'monday');

        final Map<String, dynamic> profile = (await db.db.query(
          'profiles',
        )).single;
        expect(profile['id'], 'user-2');
        expect(profile['full_name'], 'Restored Name');
        expect(profile['avatar_url'], 'user-2/avatar.jpg');
        expect(profile['currency_code'], 'INR');
      },
    );

    test(
      'replace drops local entries and unsent changes, then clears the server first',
      () async {
        final String now = DateTime.now().toIso8601String();
        Map<String, dynamic> account(String id, String userId) =>
            <String, dynamic>{
              'id': id,
              'user_id': userId,
              'name': 'Account $id',
              'type': 'cash',
              'opening_balance': '0',
              'is_active': 1,
              'created_at': now,
              'updated_at': now,
              'sync_status': 'pending',
            };
        // Saved offline before its first sync, so its user_id is still empty.
        await db.db.insert('accounts', account('unsynced', ''));
        await db.enqueue(
          SyncQueueItem(
            operation: SyncOperation.create,
            entity: 'accounts',
            entityId: 'unsynced',
            payload: account('unsynced', ''),
            createdAt: DateTime.now(),
          ),
        );
        await db.enqueue(
          SyncQueueItem(
            operation: SyncOperation.update,
            entity: 'profiles',
            entityId: 'user-1',
            payload: <String, dynamic>{'full_name': 'Typed offline'},
            createdAt: DateTime.now(),
          ),
        );
        final int systemCategories = (await db.db.query(
          'categories',
          where: 'is_system = 1',
        )).length;

        final RestoreResult result = await service.restoreBackup(
          db,
          <String, List<Map<String, dynamic>>>{
            'accounts': <Map<String, dynamic>>[account('acc-1', 'user-1')],
          },
          replaceExisting: true,
          userId: 'user-1',
        );
        expect(result.success, isTrue);

        final List<Map<String, dynamic>> accounts = await db.db.query(
          'accounts',
        );
        expect(accounts.map((Map<String, dynamic> a) => a['id']), <String>[
          'acc-1',
        ]);
        expect(
          (await db.db.query('categories', where: 'is_system = 1')).length,
          systemCategories,
        );

        final List<SyncQueueItem> queue = await db.getPendingQueue(limit: 50);
        expect(
          queue.map((SyncQueueItem q) => '${q.operation.name}:${q.entity}'),
          <String>[
            // The profile is not part of the replaced data.
            'update:profiles',
            for (final String table in BackupService.uploadTables)
              'replace:$table',
            'create:accounts',
          ],
        );
        final SyncQueueItem accountsReplace = queue.firstWhere(
          (SyncQueueItem q) =>
              q.operation == SyncOperation.replace && q.entity == 'accounts',
        );
        expect(accountsReplace.payload['keep_ids'], <String>['acc-1']);
      },
    );

    test('backup includes entries not yet synced', () async {
      final String now = DateTime.now().toIso8601String();
      for (final MapEntry<String, String> entry in <String, String>{
        'mine': 'user-1',
        'unsynced': '',
        'other': 'user-9',
      }.entries) {
        await db.db.insert('contacts', <String, dynamic>{
          'id': entry.key,
          'user_id': entry.value,
          'name': entry.key,
          'created_at': now,
          'updated_at': now,
        });
      }

      final Map<String, dynamic> backup = await service.createBackup(
        db,
        userId: 'user-1',
      );

      final List<dynamic> contacts =
          (backup['data'] as Map<String, dynamic>)['contacts'] as List<dynamic>;
      expect(
        contacts.map((dynamic c) => (c as Map<String, dynamic>)['id']),
        unorderedEquals(<String>['mine', 'unsynced']),
      );
    });
  });
}
