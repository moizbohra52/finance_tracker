import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/split.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_balances.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One group for the list screen: the group, how many live members it has
/// (including the user) and the user's net in it (positive: they are owed).
class SplitGroupSummary {
  const SplitGroupSummary({
    required this.group,
    required this.memberCount,
    required this.userNet,
  });

  final SplitGroup group;
  final int memberCount;
  final Decimal userNet;
}

/// What a derived transaction or khata entry belongs to, for the "Open in
/// group" behaviour.
class SplitLink {
  const SplitLink({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.isSettlement,
  });

  final String id;
  final String groupId;
  final String groupName;
  final bool isSettlement;
}

/// Local storage for split expenses (docs/05_FINANCIAL_LOGIC.md). Every
/// operation is one SQLite transaction holding the rows and their queue
/// items, parents enqueued first. With a null database every method throws
/// `DatabaseFailure` (production always passes the database).
class SplitRepository {
  SplitRepository(AppDatabase? database, {SyncEngine? syncEngine})
    : _db = database,
      // ignore: prefer_initializing_formals
      _syncEngine = syncEngine;

  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  AppDatabase get _database {
    final AppDatabase? db = _db;
    if (db == null) throw const DatabaseFailure();
    return db;
  }

  static Future<void> _enqueue(
    DatabaseExecutor txn,
    SyncOperation operation,
    String entity,
    String entityId,
    Map<String, dynamic> payload,
    DateTime now,
  ) => txn.insert(
    'sync_queue',
    SyncQueueItem(
      operation: operation,
      entity: entity,
      entityId: entityId,
      payload: payload,
      createdAt: now,
    ).toRow(),
  );

  /// A full local row: model columns plus timestamps and the pending flag.
  static Map<String, dynamic> _row(
    Map<String, dynamic> json,
    DateTime createdAt,
    DateTime updatedAt,
  ) => <String, dynamic>{
    ...json,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': null,
    'sync_status': 'pending',
  };

  /// Live groups, newest first, with member counts and the user's net.
  Future<List<SplitGroupSummary>> getGroups() async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'split_groups',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC, id DESC',
    );
    final List<SplitGroupSummary> groups = <SplitGroupSummary>[];
    for (final Map<String, dynamic> row in rows) {
      final SplitGroup group = SplitGroupModel.fromJson(row);
      final List<SplitMember> members = await getMembers(group.id);
      final GroupBalances balances = await _balancesOf(group.id);
      groups.add(
        SplitGroupSummary(
          group: group,
          memberCount: members.length,
          userNet: balances.netOf(SplitIds.member(group.id, null)),
        ),
      );
    }
    return groups;
  }

  Future<SplitGroup> getGroup(String groupId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'split_groups',
      where: 'id = ?',
      whereArgs: <Object>[groupId],
      limit: 1,
    );
    if (rows.isEmpty) throw const DatabaseFailure();
    return SplitGroupModel.fromJson(rows.first);
  }

  /// Live members of [groupId], the user's own member first.
  Future<List<SplitMember>> getMembers(String groupId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'split_group_members',
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
      orderBy: 'created_at ASC, id ASC',
    );
    final List<SplitMember> members = rows
        .map(SplitMemberModel.fromJson)
        .toList();
    members.sort((SplitMember a, SplitMember b) {
      final int byMe = (b.isMe ? 1 : 0).compareTo(a.isMe ? 1 : 0);
      return byMe != 0 ? byMe : a.id.compareTo(b.id);
    });
    return members;
  }

  /// One local transaction: upserts the group, the user's member, a member
  /// per friend (reviving a tombstoned one) and tombstones friends no longer
  /// listed. A removed friend with a live part or settlement is refused and
  /// nothing is written.
  Future<void> saveGroup({
    required String groupId,
    required String name,
    required List<String> friendContactIds,
  }) async {
    final AppDatabase database = _database;
    if (name.trim().isEmpty) {
      throw const UnexpectedFailure('Give the group a name');
    }
    final Set<String> friends = friendContactIds.toSet();
    if (friends.isEmpty) {
      throw const UnexpectedFailure('Add at least one friend');
    }
    final DateTime now = DateTime.now();
    final SplitGroup? existing = await _existingGroup(groupId);
    if (existing != null) {
      for (final SplitMember member in await getMembers(groupId)) {
        if (member.isMe || friends.contains(member.contactId)) continue;
        if (await _memberHasLiveActivity(member.id)) {
          throw const UnexpectedFailure(
            "This friend is in an expense or settlement and can't be removed",
          );
        }
      }
    }
    final SplitGroup group = SplitGroup(
      id: groupId,
      userId: existing?.userId ?? '',
      name: name.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final List<SplitMember> allMembers = await _allMembers(groupId);
    final Map<String, SplitMember> knownByContact = <String, SplitMember>{
      for (final SplitMember m in allMembers)
        if (m.contactId != null) m.contactId!: m,
    };
    SplitMember? knownMe;
    for (final SplitMember m in allMembers) {
      if (m.isMe) knownMe = m;
    }
    final SplitMember me = SplitMember(
      id: SplitIds.member(groupId, null),
      userId: knownMe?.userId ?? '',
      groupId: groupId,
      contactId: null,
      createdAt: knownMe?.createdAt ?? now,
      updatedAt: now,
    );
    final List<SplitMember> wanted = <SplitMember>[
      me,
      for (final String contactId in friends)
        SplitMember(
          id: SplitIds.member(groupId, contactId),
          userId: knownByContact[contactId]?.userId ?? '',
          groupId: groupId,
          contactId: contactId,
          createdAt: knownByContact[contactId]?.createdAt ?? now,
          updatedAt: now,
        ),
    ];
    final List<SplitMember> toRemove = <SplitMember>[
      for (final MapEntry<String, SplitMember> e in knownByContact.entries)
        if (!friends.contains(e.key)) e.value,
    ];

    await database.db.transaction((DatabaseExecutor txn) async {
      final Map<String, dynamic> groupJson = SplitGroupModel.toJson(group);
      await txn.insert(
        'split_groups',
        _row(groupJson, group.createdAt, group.updatedAt),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _enqueue(
        txn,
        existing == null ? SyncOperation.create : SyncOperation.update,
        'split_groups',
        group.id,
        groupJson,
        now,
      );
      for (final SplitMember member in wanted) {
        final bool isNew = member.isMe
            ? knownMe == null
            : !knownByContact.containsKey(member.contactId);
        final Map<String, dynamic> json = SplitMemberModel.toJson(member);
        await txn.insert(
          'split_group_members',
          _row(json, member.createdAt, member.updatedAt),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _enqueue(
          txn,
          isNew ? SyncOperation.create : SyncOperation.update,
          'split_group_members',
          member.id,
          json,
          now,
        );
      }
      for (final SplitMember member in toRemove) {
        await txn.update(
          'split_group_members',
          <String, dynamic>{
            'deleted_at': now.toUtc().toIso8601String(),
            'updated_at': now.toUtc().toIso8601String(),
            'sync_status': 'pending',
          },
          where: 'id = ?',
          whereArgs: <Object>[member.id],
        );
        await _enqueue(
          txn,
          SyncOperation.delete,
          'split_group_members',
          member.id,
          tombstone(),
          now,
        );
      }
    });
    _syncEngine?.notifyNewQueueItem();
  }

  /// The name of a live group that has a live member for [contactId], so the
  /// contact cannot be deleted, or null.
  Future<String?> groupNameBlockingContactDelete(String contactId) async {
    final AppDatabase? database = _db;
    if (database == null) throw const DatabaseFailure();
    final List<Map<String, dynamic>> rows = await database.db.rawQuery(
      '''
      SELECT g.name FROM split_groups g
      JOIN split_group_members m ON m.group_id = g.id
      WHERE m.contact_id = ? AND m.deleted_at IS NULL AND g.deleted_at IS NULL
      LIMIT 1
    ''',
      <Object>[contactId],
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String;
  }

  /// Resolves the given expense and settlement ids to their groups; rows
  /// whose group is deleted are omitted.
  Future<Map<String, SplitLink>> getLinks({
    Iterable<String> expenseIds = const <String>[],
    Iterable<String> settlementIds = const <String>[],
  }) async {
    final AppDatabase? database = _db;
    if (database == null) throw const DatabaseFailure();
    final Map<String, SplitLink> links = <String, SplitLink>{};
    Future<void> resolve(
      Iterable<String> ids,
      String table,
      bool isSettlement,
    ) async {
      final List<String> idList = ids.toList();
      if (idList.isEmpty) return;
      final List<Map<String, dynamic>> rows = await database.db.rawQuery('''
        SELECT r.id AS row_id, g.id AS group_id, g.name AS group_name
        FROM $table r
        JOIN split_groups g ON g.id = r.group_id
        WHERE g.deleted_at IS NULL AND r.id IN (
          ${List<String>.filled(idList.length, '?').join(', ')}
        )
      ''', idList);
      for (final Map<String, dynamic> row in rows) {
        links[row['row_id'] as String] = SplitLink(
          id: row['row_id'] as String,
          groupId: row['group_id'] as String,
          groupName: row['group_name'] as String,
          isSettlement: isSettlement,
        );
      }
    }

    await resolve(expenseIds, 'split_expenses', false);
    await resolve(settlementIds, 'split_settlements', true);
    return links;
  }

  Future<GroupBalances> _balancesOf(String groupId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> expenseRows = await database.db.query(
      'split_expenses',
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
    );
    final List<SplitExpense> expenses = expenseRows
        .map(SplitExpenseModel.fromJson)
        .toList();
    final Map<String, List<SplitPart>> partsByExpense =
        <String, List<SplitPart>>{};
    for (final SplitExpense expense in expenses) {
      final List<Map<String, dynamic>> partRows = await database.db.query(
        'split_expense_parts',
        where: 'split_expense_id = ? AND deleted_at IS NULL',
        whereArgs: <Object>[expense.id],
      );
      partsByExpense[expense.id] = partRows
          .map(SplitPartModel.fromJson)
          .toList();
    }
    final List<Map<String, dynamic>> settlementRows = await database.db.query(
      'split_settlements',
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
    );
    return SplitBalances.compute(
      meId: SplitIds.member(groupId, null),
      expenses: expenses,
      partsByExpense: partsByExpense,
      settlements: settlementRows.map(SplitSettlementModel.fromJson).toList(),
    );
  }

  Future<SplitGroup?> _existingGroup(String groupId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'split_groups',
      where: 'id = ?',
      whereArgs: <Object>[groupId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SplitGroupModel.fromJson(rows.first);
  }

  /// Every member row of the group, live and tombstoned.
  Future<List<SplitMember>> _allMembers(String groupId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'split_group_members',
      where: 'group_id = ?',
      whereArgs: <Object>[groupId],
    );
    return rows.map(SplitMemberModel.fromJson).toList();
  }

  /// True when [memberId] has a live part or settlement.
  Future<bool> _memberHasLiveActivity(String memberId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> parts = await database.db.query(
      'split_expense_parts',
      where: 'member_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[memberId],
      limit: 1,
    );
    if (parts.isNotEmpty) return true;
    final List<Map<String, dynamic>> settlements = await database.db.query(
      'split_settlements',
      where: '(from_member_id = ? OR to_member_id = ?) AND deleted_at IS NULL',
      whereArgs: <Object>[memberId, memberId],
      limit: 1,
    );
    return settlements.isNotEmpty;
  }
}
