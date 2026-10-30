import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/contact_datasource.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:flutter_test/flutter_test.dart';

/// A photo is saved on its own: only avatar_url goes up, and editing the
/// contact or group afterwards keeps it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = await AppDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  Future<List<SyncQueueItem>> queuedFor(String entity) async =>
      (await database.getPendingQueue(
        limit: 1000,
      )).where((SyncQueueItem i) => i.entity == entity).toList();

  test('a contact photo is its own update and survives an edit', () async {
    final ContactRepository contacts = ContactRepository(
      ContactLocalDatasourceImpl(database, SyncEngine(database: database)),
    );
    final DateTime now = DateTime(2026, 10, 30);
    final Contact amit = Contact(
      id: 'c1',
      userId: 'u',
      name: 'Amit',
      openingBalance: Decimal.zero,
      openingBalanceType: 'receivable',
      createdAt: now,
      updatedAt: now,
    );
    await contacts.createContact(amit);

    await contacts.setPhoto('c1', 'u/contacts/c1-1.jpg');

    expect(
      (await contacts.getContactById('c1')).avatarPath,
      'u/contacts/c1-1.jpg',
    );
    final SyncQueueItem photo = (await queuedFor('contacts')).last;
    expect(photo.operation, SyncOperation.update);
    expect(photo.payload, <String, dynamic>{
      'avatar_url': 'u/contacts/c1-1.jpg',
    });
    // A plain create or edit never sends the column.
    expect(
      (await queuedFor('contacts')).first.payload.containsKey('avatar_url'),
      isFalse,
    );

    await contacts.updateContact(
      Contact(
        id: 'c1',
        userId: 'u',
        name: 'Amit Kumar',
        openingBalance: Decimal.zero,
        openingBalanceType: 'receivable',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final Contact edited = await contacts.getContactById('c1');
    expect(edited.name, 'Amit Kumar');
    expect(edited.avatarPath, 'u/contacts/c1-1.jpg');

    await contacts.setPhoto('c1', null);
    expect((await contacts.getContactById('c1')).avatarPath, isNull);
    expect((await queuedFor('contacts')).last.payload, <String, dynamic>{
      'avatar_url': null,
    });
  });

  test('a group photo is its own update and survives a rename', () async {
    final SplitRepository split = SplitRepository(
      database,
      syncEngine: SyncEngine(database: database),
    );
    await split.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1'],
    );

    await split.setGroupPhoto('g1', 'u/groups/g1-1.jpg');

    expect((await split.getGroup('g1')).avatarPath, 'u/groups/g1-1.jpg');
    expect((await queuedFor('split_groups')).last.payload, <String, dynamic>{
      'avatar_url': 'u/groups/g1-1.jpg',
    });

    await split.saveGroup(
      groupId: 'g1',
      name: 'Goa trip',
      friendContactIds: <String>['c1'],
    );
    final SplitGroup renamed = await split.getGroup('g1');
    expect(renamed.name, 'Goa trip');
    expect(renamed.avatarPath, 'u/groups/g1-1.jpg');
    expect(
      (await queuedFor('split_groups')).last.payload.containsKey('avatar_url'),
      isFalse,
    );
  });
}
