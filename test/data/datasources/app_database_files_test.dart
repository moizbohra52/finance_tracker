import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> _accounts(AppDatabase database) async =>
    (await database.db.query('accounts')).length;

Future<void> _addAccount(AppDatabase database, String id) =>
    database.db.insert('accounts', <String, Object?>{
      'id': id,
      'user_id': 'u',
      'name': 'Cash',
      'type': 'cash',
      'opening_balance': '0',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });

void main() {
  group('one database per signed-in account', () {
    test('switching shows only the active account\'s rows', () async {
      final AppDatabase database = await AppDatabase.inMemoryFiles(
        userId: 'user-1',
      );
      await _addAccount(database, 'acc-1');

      await database.openFor('user-2');
      expect(database.userId, 'user-2');
      expect(await _accounts(database), 0);

      await database.openFor('user-1');
      expect(await _accounts(database), 1, reason: 'kept while away');
    });

    test('a new account file starts with the system categories', () async {
      final AppDatabase database = await AppDatabase.inMemoryFiles(
        userId: 'user-2',
      );
      final List<Map<String, Object?>> categories = await database.db.query(
        'categories',
        where: 'is_system = 1',
      );
      expect(categories, isNotEmpty);
    });

    test('removing a signed-out account deletes only its data', () async {
      final AppDatabase database = await AppDatabase.inMemoryFiles(
        userId: 'user-2',
      );
      await _addAccount(database, 'acc-2');
      await database.openFor('user-1');
      await _addAccount(database, 'acc-1');

      await database.removeUser('user-2');

      expect(await _accounts(database), 1);
      await database.openFor('user-2');
      expect(await _accounts(database), 0, reason: 'a fresh, empty file');
    });

    test('the open account\'s file cannot be deleted', () async {
      final AppDatabase database = await AppDatabase.inMemoryFiles(
        userId: 'user-1',
      );
      expect(() => database.removeUser('user-1'), throwsStateError);
    });

    test('a single shared database is cleared instead', () async {
      final AppDatabase database = await AppDatabase.inMemory();
      await _addAccount(database, 'acc-1');
      await database.removeUser('user-1');
      expect(await _accounts(database), 0);
    });

    test('file names are per account and refuse path tricks', () {
      final String shared = AppEnv.databaseName;
      expect(AppDatabase.fileNameFor(null), shared);
      expect(
        AppDatabase.fileNameFor('5f0c6c1e-1111-4222-8333-444455556666'),
        '${shared.substring(0, shared.length - 3)}'
        '_5f0c6c1e-1111-4222-8333-444455556666.db',
      );
      expect(() => AppDatabase.fileNameFor('../other'), throwsArgumentError);
    });
  });
}
