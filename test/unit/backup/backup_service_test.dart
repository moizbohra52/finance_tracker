import 'dart:convert';
import 'package:finance_tracker/core/services/backup_service.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
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
  });
}
