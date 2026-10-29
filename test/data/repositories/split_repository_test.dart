import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SplitRepository repo;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repo = SplitRepository(
      database,
      syncEngine: SyncEngine(database: database),
    );
  });

  tearDown(() async {
    await database.close();
  });

  final DateTime now = DateTime(2026, 10, 26, 12);

  Future<List<SyncQueueItem>> queue() async => database.getPendingQueue();

  /// Inserts a live part for [memberId] directly, without an expense.
  Future<void> insertPart(String memberId) async {
    await database.db.insert('split_expense_parts', <String, Object?>{
      'id': 'part-$memberId',
      'user_id': null,
      'split_expense_id': 'exp-x',
      'member_id': memberId,
      'paid_amount': '0',
      'share_amount': '10',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  test(
    'saveGroup writes group + me + friends and queues them in order',
    () async {
      await repo.saveGroup(
        groupId: 'g1',
        name: 'Goa',
        friendContactIds: <String>['c1', 'c2'],
      );

      final SplitGroup group = await repo.getGroup('g1');
      expect(group.name, 'Goa');
      expect(group.deletedAt, isNull);
      final List<SplitMember> members = await repo.getMembers('g1');
      expect(members.length, 3);
      expect(members.first.isMe, isTrue);
      expect(members.first.id, SplitIds.member('g1', null));
      expect(
        members.map((SplitMember m) => m.contactId).skip(1).toSet(),
        <String>{'c1', 'c2'},
      );

      final List<SyncQueueItem> items = await queue();
      final List<String> entities = items
          .map((SyncQueueItem i) => i.entity)
          .toList();
      expect(entities.first, 'split_groups');
      expect(
        entities.where((String e) => e == 'split_group_members').length,
        3,
      );
      expect(entities.where((String e) => e == 'split_groups').length, 1);
      expect(
        items.first.entityId,
        'g1',
        reason: 'the group is queued before its members',
      );
      expect(items.first.operation, SyncOperation.create);
    },
  );

  test('saving again with the same ids adds no extra live rows', () async {
    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1'],
    );
    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa renamed',
      friendContactIds: <String>['c1'],
    );

    final List<SplitMember> members = await repo.getMembers('g1');
    expect(members.length, 2);
    final SplitGroup group = await repo.getGroup('g1');
    expect(group.name, 'Goa renamed');
  });

  test('removing a friend without parts tombstones them', () async {
    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1', 'c2'],
    );
    final int queueLengthBefore = (await queue()).length;

    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1'],
    );

    final List<SplitMember> live = await repo.getMembers('g1');
    expect(live.map((SplitMember m) => m.contactId), <String?>[null, 'c1']);
    final List<SyncQueueItem> items = await queue();
    expect(items.length, greaterThan(queueLengthBefore));
    expect(
      items.where((SyncQueueItem i) => i.operation == SyncOperation.delete),
      isNotEmpty,
      reason: 'the removed member is queued as a delete',
    );
  });

  test(
    'removing a friend with a live part is refused and writes nothing',
    () async {
      await repo.saveGroup(
        groupId: 'g1',
        name: 'Goa',
        friendContactIds: <String>['c1', 'c2'],
      );
      final String memberC2 = SplitIds.member('g1', 'c2');
      await insertPart(memberC2);
      final int queueLengthBefore = (await queue()).length;

      await expectLater(
        repo.saveGroup(
          groupId: 'g1',
          name: 'Goa',
          friendContactIds: <String>['c1'],
        ),
        throwsA(
          isA<UnexpectedFailure>().having(
            (UnexpectedFailure e) => e.message,
            'message',
            "This friend is in an expense or settlement and can't be removed",
          ),
        ),
      );
      final List<SplitMember> live = await repo.getMembers('g1');
      expect(live.length, 3, reason: 'nothing was written');
      expect((await queue()).length, queueLengthBefore);
    },
  );

  test('re-adding a removed friend revives the same member id', () async {
    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1', 'c2'],
    );
    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1'],
    );
    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1', 'c2'],
    );

    final List<SplitMember> live = await repo.getMembers('g1');
    expect(live.length, 3);
    expect(
      live.where((SplitMember m) => m.contactId == 'c2').single.id,
      SplitIds.member('g1', 'c2'),
    );
  });

  test('blank name and empty friends are refused', () async {
    await expectLater(
      repo.saveGroup(
        groupId: 'g1',
        name: '   ',
        friendContactIds: <String>['c1'],
      ),
      throwsA(
        isA<UnexpectedFailure>().having(
          (UnexpectedFailure e) => e.message,
          'message',
          'Give the group a name',
        ),
      ),
    );
    await expectLater(
      repo.saveGroup(groupId: 'g1', name: 'Goa', friendContactIds: <String>[]),
      throwsA(
        isA<UnexpectedFailure>().having(
          (UnexpectedFailure e) => e.message,
          'message',
          'Add at least one friend',
        ),
      ),
    );
    final List<Map<String, Object?>> groups = await database.db.query(
      'split_groups',
    );
    expect(groups, isEmpty, reason: 'nothing was written');
  });

  test('groupNameBlockingContactDelete finds live groups only', () async {
    expect(await repo.groupNameBlockingContactDelete('c1'), isNull);

    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1'],
    );
    expect(await repo.groupNameBlockingContactDelete('c1'), 'Goa');

    await database.db.update(
      'split_groups',
      <String, Object?>{'deleted_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: <Object>['g1'],
    );
    expect(await repo.groupNameBlockingContactDelete('c1'), isNull);
  });

  test('getGroups returns memberCount and userNet', () async {
    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1'],
    );
    List<SplitGroupSummary> groups = await repo.getGroups();
    expect(groups.length, 1);
    expect(groups.single.memberCount, 2);
    expect(groups.single.userNet, Decimal.zero);

    // A second group, saved later, comes first (newest first).
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.saveGroup(
      groupId: 'g2',
      name: 'Lunch',
      friendContactIds: <String>['c2'],
    );
    groups = await repo.getGroups();
    expect(groups.map((SplitGroupSummary g) => g.group.id).toList(), <String>[
      'g2',
      'g1',
    ]);
  });

  test('getLinks resolves rows and skips deleted groups', () async {
    await repo.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c1'],
    );
    final String meId = SplitIds.member('g1', null);
    await database.db.insert('split_expenses', <String, Object?>{
      'id': 'e1',
      'group_id': 'g1',
      'title': 'Dinner',
      'total_amount': '1200',
      'expense_date': now.toIso8601String(),
      'split_mode': 'equal',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await database.db.insert('split_settlements', <String, Object?>{
      'id': 's1',
      'group_id': 'g1',
      'from_member_id': meId,
      'to_member_id': meId,
      'amount': '100',
      'settled_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await database.db.insert('split_expenses', <String, Object?>{
      'id': 'e2',
      'group_id': 'g2',
      'title': 'Orphan',
      'total_amount': '10',
      'expense_date': now.toIso8601String(),
      'split_mode': 'equal',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final Map<String, SplitLink> links = await repo.getLinks(
      expenseIds: <String>['e1', 'e2'],
      settlementIds: <String>['s1'],
    );
    expect(links.containsKey('e1'), isTrue);
    expect(links['e1']!.groupName, 'Goa');
    expect(links['e1']!.isSettlement, isFalse);
    expect(links.containsKey('s1'), isTrue);
    expect(links['s1']!.isSettlement, isTrue);
    expect(
      links.containsKey('e2'),
      isFalse,
      reason: 'its group does not exist',
    );
  });

  test('a null database makes every method throw DatabaseFailure', () async {
    final SplitRepository empty = SplitRepository(null);
    await expectLater(empty.getGroups(), throwsA(isA<DatabaseFailure>()));
    await expectLater(empty.getGroup('g1'), throwsA(isA<DatabaseFailure>()));
    await expectLater(empty.getMembers('g1'), throwsA(isA<DatabaseFailure>()));
    await expectLater(
      empty.saveGroup(
        groupId: 'g1',
        name: 'Goa',
        friendContactIds: <String>['c1'],
      ),
      throwsA(isA<DatabaseFailure>()),
    );
    await expectLater(
      empty.groupNameBlockingContactDelete('c1'),
      throwsA(isA<DatabaseFailure>()),
    );
    await expectLater(
      empty.getLinks(expenseIds: <String>['e1']),
      throwsA(isA<DatabaseFailure>()),
    );
  });
}
