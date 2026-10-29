import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/contact_transaction.dart';
import 'package:finance_tracker/data/models/split.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/split_balances.dart';
import 'package:finance_tracker/domain/services/split_calculator.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// One expense with its live parts, for the form's edit mode.
class SplitExpenseDetail {
  const SplitExpenseDetail({required this.expense, required this.parts});

  final SplitExpense expense;
  final List<SplitPart> parts;
}

/// Everything the group detail screen shows.
class SplitGroupDetail {
  const SplitGroupDetail({
    required this.group,
    required this.members,
    required this.balances,
    required this.totalSpent,
    required this.userShareTotal,
  });

  final SplitGroup group;
  final List<SplitMember> members;
  final GroupBalances balances;
  final Decimal totalSpent;
  final Decimal userShareTotal;
}

/// One row of the group's activity feed.
sealed class SplitActivityItem {
  const SplitActivityItem();

  DateTime get date;
}

class SplitActivityExpense extends SplitActivityItem {
  const SplitActivityExpense({required this.expense, required this.userPart});

  final SplitExpense expense;

  /// The user's own part of the expense, null when they took none.
  final SplitPart? userPart;

  @override
  DateTime get date => expense.expenseDate;
}

class SplitActivitySettlement extends SplitActivityItem {
  const SplitActivitySettlement({required this.settlement});

  final SplitSettlement settlement;

  @override
  DateTime get date => settlement.settledAt;
}

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

  /// One expense with its live parts, oldest first.
  Future<SplitExpenseDetail> getExpense(String expenseId) async {
    final AppDatabase database = _database;
    final SplitExpense expense = await _expenseRow(expenseId);
    final List<Map<String, dynamic>> partRows = await database.db.query(
      'split_expense_parts',
      where: 'split_expense_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[expenseId],
      orderBy: 'created_at ASC, id ASC',
    );
    return SplitExpenseDetail(
      expense: expense,
      parts: partRows.map(SplitPartModel.fromJson).toList(),
    );
  }

  /// Validates the expense against its parts and writes everything in one
  /// local transaction: the expense, its parts (tombstoning removed ones) and
  /// the user's derived `transactions` and `contact_transactions` rows
  /// (docs/05_FINANCIAL_LOGIC.md). A retry with the same ids upserts.
  Future<void> saveExpense({
    required SplitExpense expense,
    required List<SplitPart> parts,
  }) async {
    final AppDatabase database = _database;
    final List<SplitMember> members = await getMembers(expense.groupId);
    SplitMember? me;
    final Map<String, SplitMember> byId = <String, SplitMember>{
      for (final SplitMember m in members) m.id: m,
    };
    for (final SplitMember m in members) {
      if (m.isMe) me = m;
    }
    if (me == null) {
      throw const UnexpectedFailure('Add at least one friend');
    }
    final Map<String, Decimal> paid = <String, Decimal>{
      for (final SplitPart p in parts) p.memberId: p.paidAmount,
    };
    final Map<String, Decimal> shares = <String, Decimal>{
      for (final SplitPart p in parts) p.memberId: p.shareAmount,
    };
    final String? message = SplitCalculator.validate(
      total: expense.totalAmount,
      paid: paid,
      shares: shares,
      meId: me.id,
      categoryId: expense.categoryId,
      accountId: expense.accountId,
    );
    if (message != null) throw UnexpectedFailure(message);
    final SplitUserRows rows = SplitCalculator.userRows(
      total: expense.totalAmount,
      meId: me.id,
      paid: paid,
      shares: shares,
    );
    final SplitGroup group =
        await _existingGroup(expense.groupId) ??
        SplitGroup(
          id: expense.groupId,
          userId: '',
          name: '',
          createdAt: expense.createdAt,
          updatedAt: expense.updatedAt,
        );
    final DateTime now = DateTime.now();
    final SplitExpense? existingExpense = await _expenseOrNull(expense.id);

    // The parts that stay live, with their deterministic ids.
    final List<SplitPart> wantedParts = <SplitPart>[
      for (final SplitPart p in parts)
        SplitPart(
          id: SplitIds.part(expense.id, p.memberId),
          userId: byId[p.memberId]?.userId ?? p.userId,
          splitExpenseId: expense.id,
          memberId: p.memberId,
          paidAmount: p.paidAmount,
          shareAmount: p.shareAmount,
          shareInput: p.shareInput,
          createdAt: p.createdAt,
          updatedAt: now,
        ),
    ];
    final Set<String> wantedPartIds = wantedParts
        .map((SplitPart p) => p.id)
        .toSet();

    // The derived rows the user's books need now.
    final List<Transaction> derivedTransactions = <Transaction>[];
    final List<ContactTransaction> derivedKhata = <ContactTransaction>[];
    if (rows.expenseShare > Decimal.zero) {
      derivedTransactions.add(
        Transaction(
          id: SplitIds.expenseShare(expense.id),
          userId: '',
          accountId: expense.accountId!,
          categoryId: expense.categoryId,
          contactId: null,
          type: TransactionType.expense,
          amount: rows.expenseShare,
          transactionDate: expense.expenseDate,
          note: expense.note,
          description: expense.title,
          splitExpenseId: expense.id,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    if (rows.balanceAmount > Decimal.zero) {
      derivedTransactions.add(
        Transaction(
          id: SplitIds.expenseBalance(expense.id),
          userId: '',
          accountId: expense.accountId!,
          categoryId: null,
          contactId: null,
          type: rows.balanceIsPaidForOthers
              ? TransactionType.payment_made
              : TransactionType.payment_received,
          amount: rows.balanceAmount,
          transactionDate: expense.expenseDate,
          description: rows.balanceIsPaidForOthers
              ? 'Split: paid for others · @group'.trParams(<String, String>{
                  'group': group.name,
                })
              : 'Split: others paid your share · @group'.trParams(
                  <String, String>{'group': group.name},
                ),
          splitExpenseId: expense.id,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    for (final MapEntry<String, Decimal> net in rows.contactNets.entries) {
      if (net.value == Decimal.zero) continue;
      final SplitMember? member = byId[net.key];
      if (member == null || member.isMe || member.contactId == null) continue;
      derivedKhata.add(
        ContactTransaction(
          id: SplitIds.expenseContact(expense.id, member.contactId!),
          userId: '',
          contactId: member.contactId!,
          type: net.value > Decimal.zero
              ? ContactTransactionType.credit
              : ContactTransactionType.debit,
          amount: net.value.abs(),
          transactionDate: expense.expenseDate,
          note: '@group · @title'.trParams(<String, String>{
            'group': group.name,
            'title': expense.title,
          }),
          splitExpenseId: expense.id,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    await database.db.transaction((DatabaseExecutor txn) async {
      // 1. The expense.
      final Map<String, dynamic> expenseJson = SplitExpenseModel.toJson(
        expense.copyWith(updatedAt: now),
      );
      await txn.insert(
        'split_expenses',
        _row(expenseJson, existingExpense?.createdAt ?? expense.createdAt, now),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _enqueue(
        txn,
        existingExpense == null ? SyncOperation.create : SyncOperation.update,
        'split_expenses',
        expense.id,
        expenseJson,
        now,
      );
      // 2. The parts; removed ones are tombstoned.
      final List<Map<String, dynamic>> existingParts = await txn.query(
        'split_expense_parts',
        columns: <String>['id'],
        where: 'split_expense_id = ? AND deleted_at IS NULL',
        whereArgs: <Object>[expense.id],
      );
      final Set<String> existingPartIds = <String>{
        for (final Map<String, dynamic> r in existingParts) r['id'] as String,
      };
      for (final SplitPart part in wantedParts) {
        final Map<String, dynamic> json = SplitPartModel.toJson(part);
        await txn.insert(
          'split_expense_parts',
          _row(json, part.createdAt, now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _enqueue(
          txn,
          existingPartIds.contains(part.id)
              ? SyncOperation.update
              : SyncOperation.create,
          'split_expense_parts',
          part.id,
          json,
          now,
        );
      }
      for (final Map<String, dynamic> stale in existingParts) {
        final String id = stale['id'] as String;
        if (wantedPartIds.contains(id)) continue;
        await _tombstoneLive(txn, 'split_expense_parts', 'id = ?', id, now);
      }
      // 3. The user's derived transactions.
      final List<Map<String, dynamic>> existingTxns = await txn.query(
        'transactions',
        columns: <String>['id', 'deleted_at'],
        where: 'split_expense_id = ?',
        whereArgs: <Object>[expense.id],
      );
      final Set<String> liveTxnIds = <String>{
        for (final Map<String, dynamic> r in existingTxns)
          if (r['deleted_at'] == null) r['id'] as String,
      };
      for (final Transaction t in derivedTransactions) {
        final Map<String, dynamic> json = TransactionModel.fromEntity(
          t,
        ).toJson();
        await txn.insert(
          'transactions',
          _row(json, now, now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _enqueue(
          txn,
          liveTxnIds.contains(t.id)
              ? SyncOperation.update
              : SyncOperation.create,
          'transactions',
          t.id,
          json,
          now,
        );
      }
      for (final String id in liveTxnIds) {
        if (derivedTransactions.any((Transaction t) => t.id == id)) continue;
        await _tombstoneLive(txn, 'transactions', 'id = ?', id, now);
      }
      // 4. The user's derived khata entries.
      final List<Map<String, dynamic>> existingKhata = await txn.query(
        'contact_transactions',
        columns: <String>['id', 'deleted_at'],
        where: 'split_expense_id = ?',
        whereArgs: <Object>[expense.id],
      );
      final Set<String> liveKhataIds = <String>{
        for (final Map<String, dynamic> r in existingKhata)
          if (r['deleted_at'] == null) r['id'] as String,
      };
      for (final ContactTransaction c in derivedKhata) {
        final Map<String, dynamic> json = ContactTransactionModel.fromEntity(
          c,
        ).toJson();
        await txn.insert(
          'contact_transactions',
          _row(json, now, now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _enqueue(
          txn,
          liveKhataIds.contains(c.id)
              ? SyncOperation.update
              : SyncOperation.create,
          'contact_transactions',
          c.id,
          json,
          now,
        );
      }
      for (final String id in liveKhataIds) {
        if (derivedKhata.any((ContactTransaction c) => c.id == id)) continue;
        await _tombstoneLive(txn, 'contact_transactions', 'id = ?', id, now);
      }
    });
    _syncEngine?.notifyNewQueueItem();
  }

  /// Soft-deletes the expense, its parts and every derived row linked to it,
  /// one queue delete per row.
  Future<void> deleteExpense(String expenseId) async {
    final AppDatabase database = _database;
    final DateTime now = DateTime.now();
    await database.db.transaction((DatabaseExecutor txn) async {
      await _tombstoneLive(txn, 'split_expenses', 'id = ?', expenseId, now);
      final List<String> partIds = await _liveIds(
        txn,
        'split_expense_parts',
        'split_expense_id = ?',
        expenseId,
      );
      for (final String id in partIds) {
        await _tombstoneLive(txn, 'split_expense_parts', 'id = ?', id, now);
      }
      for (final String table in <String>[
        'transactions',
        'contact_transactions',
      ]) {
        final List<String> ids = await _liveIds(
          txn,
          table,
          'split_expense_id = ?',
          expenseId,
        );
        for (final String id in ids) {
          await _tombstoneLive(txn, table, 'id = ?', id, now);
        }
      }
    });
    _syncEngine?.notifyNewQueueItem();
  }

  Future<SplitSettlement> _settlementRow(String settlementId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'split_settlements',
      where: 'id = ?',
      whereArgs: <Object>[settlementId],
      limit: 1,
    );
    if (rows.isEmpty) throw const DatabaseFailure();
    return SplitSettlementModel.fromJson(rows.first);
  }

  Future<SplitSettlement> getSettlement(String settlementId) =>
      _settlementRow(settlementId);

  /// Writes the settlement and, when the user is a party, its khata entry and
  /// account movement, in one local transaction (settlement first). A
  /// settlement between two friends writes no derived rows and refuses an
  /// account. A retry with the same id upserts; clearing the account on an
  /// edit tombstones the `:account` row.
  Future<void> saveSettlement(SplitSettlement settlement) async {
    final AppDatabase database = _database;
    if (settlement.fromMemberId == settlement.toMemberId) {
      throw const UnexpectedFailure('Choose two different people');
    }
    if (settlement.amount <= Decimal.zero) {
      throw const UnexpectedFailure('Amount must be more than zero');
    }
    final List<SplitMember> members = await getMembers(settlement.groupId);
    final Map<String, SplitMember> byId = <String, SplitMember>{
      for (final SplitMember m in members) m.id: m,
    };
    final SplitSettlement? existing = await _settlementOrNull(settlement.id);
    final SplitMember? from = byId[settlement.fromMemberId];
    final SplitMember? to = byId[settlement.toMemberId];
    final bool fromIsMe = from?.isMe ?? false;
    final bool toIsMe = to?.isMe ?? false;
    final bool userIsParty = fromIsMe || toIsMe;
    final SplitMember? friend = fromIsMe ? to : (toIsMe ? from : null);
    if (!userIsParty && settlement.accountId != null) {
      throw const UnexpectedFailure(
        'Only a settlement with you can use an account',
      );
    }
    if (userIsParty && (friend == null || friend.contactId == null)) {
      throw const UnexpectedFailure('Add at least one friend');
    }
    final SplitGroup group =
        await _existingGroup(settlement.groupId) ??
        SplitGroup(
          id: settlement.groupId,
          userId: '',
          name: '',
          createdAt: settlement.createdAt,
          updatedAt: settlement.updatedAt,
        );
    final DateTime now = DateTime.now();
    final String text = 'Settlement · @group'.trParams(<String, String>{
      'group': group.name,
    });

    // The derived rows: a khata payment always, an account movement only
    // with an account. A friend → user settlement is money received.
    final bool received = toIsMe;
    final List<ContactTransaction> khataRows = <ContactTransaction>[
      if (userIsParty)
        ContactTransaction(
          id: SplitIds.settlementKhata(settlement.id),
          userId: '',
          contactId: friend!.contactId!,
          type: received
              ? ContactTransactionType.paymentReceived
              : ContactTransactionType.paymentMade,
          amount: settlement.amount,
          transactionDate: settlement.settledAt,
          note: text,
          splitSettlementId: settlement.id,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
        ),
    ];
    final List<Transaction> txnRows = <Transaction>[
      if (userIsParty && settlement.accountId != null)
        Transaction(
          id: SplitIds.settlementAccount(settlement.id),
          userId: '',
          accountId: settlement.accountId!,
          categoryId: null,
          contactId: friend!.contactId,
          type: received
              ? TransactionType.payment_received
              : TransactionType.payment_made,
          amount: settlement.amount,
          transactionDate: settlement.settledAt,
          description: text,
          splitSettlementId: settlement.id,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
        ),
    ];

    await database.db.transaction((DatabaseExecutor txn) async {
      final Map<String, dynamic> json = SplitSettlementModel.toJson(
        settlement.copyWith(updatedAt: now),
      );
      await txn.insert(
        'split_settlements',
        _row(json, existing?.createdAt ?? settlement.createdAt, now),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _enqueue(
        txn,
        existing == null ? SyncOperation.create : SyncOperation.update,
        'split_settlements',
        settlement.id,
        json,
        now,
      );
      final List<Map<String, dynamic>> liveKhata = await txn.query(
        'contact_transactions',
        columns: <String>['id'],
        where: 'split_settlement_id = ? AND deleted_at IS NULL',
        whereArgs: <Object>[settlement.id],
      );
      for (final ContactTransaction c in khataRows) {
        final Map<String, dynamic> row = ContactTransactionModel.fromEntity(
          c,
        ).toJson();
        await txn.insert(
          'contact_transactions',
          _row(row, c.createdAt, now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _enqueue(
          txn,
          liveKhata.any((Map<String, dynamic> r) => r['id'] == c.id)
              ? SyncOperation.update
              : SyncOperation.create,
          'contact_transactions',
          c.id,
          row,
          now,
        );
      }
      for (final Map<String, dynamic> stale in liveKhata) {
        final String id = stale['id'] as String;
        if (khataRows.any((ContactTransaction c) => c.id == id)) continue;
        await _tombstoneLive(txn, 'contact_transactions', 'id = ?', id, now);
      }
      final List<Map<String, dynamic>> liveTxns = await txn.query(
        'transactions',
        columns: <String>['id'],
        where: 'split_settlement_id = ? AND deleted_at IS NULL',
        whereArgs: <Object>[settlement.id],
      );
      for (final Transaction t in txnRows) {
        final Map<String, dynamic> row = TransactionModel.fromEntity(
          t,
        ).toJson();
        await txn.insert(
          'transactions',
          _row(row, t.createdAt, now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _enqueue(
          txn,
          liveTxns.any((Map<String, dynamic> r) => r['id'] == t.id)
              ? SyncOperation.update
              : SyncOperation.create,
          'transactions',
          t.id,
          row,
          now,
        );
      }
      for (final Map<String, dynamic> stale in liveTxns) {
        final String id = stale['id'] as String;
        if (txnRows.any((Transaction t) => t.id == id)) continue;
        await _tombstoneLive(txn, 'transactions', 'id = ?', id, now);
      }
    });
    _syncEngine?.notifyNewQueueItem();
  }

  /// Soft-deletes the settlement and every derived row linked to it.
  Future<void> deleteSettlement(String settlementId) async {
    final AppDatabase database = _database;
    final DateTime now = DateTime.now();
    await database.db.transaction((DatabaseExecutor txn) async {
      await _tombstoneLive(
        txn,
        'split_settlements',
        'id = ?',
        settlementId,
        now,
      );
      for (final String table in <String>[
        'transactions',
        'contact_transactions',
      ]) {
        final List<String> ids = await _liveIds(
          txn,
          table,
          'split_settlement_id = ?',
          settlementId,
        );
        for (final String id in ids) {
          await _tombstoneLive(txn, table, 'id = ?', id, now);
        }
      }
    });
    _syncEngine?.notifyNewQueueItem();
  }

  /// Soft-deletes the group and everything it owns: expenses, parts, derived
  /// rows, settlements, members, the group. One local transaction.
  Future<void> deleteGroup(String groupId) async {
    final AppDatabase database = _database;
    final DateTime now = DateTime.now();
    final List<Map<String, dynamic>> expenseRows = await database.db.query(
      'split_expenses',
      columns: <String>['id'],
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
    );
    final List<String> expenseIds = <String>[
      for (final Map<String, dynamic> r in expenseRows) r['id'] as String,
    ];
    final List<Map<String, dynamic>> settlementRows = await database.db.query(
      'split_settlements',
      columns: <String>['id'],
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
    );
    final List<String> settlementIds = <String>[
      for (final Map<String, dynamic> r in settlementRows) r['id'] as String,
    ];
    await database.db.transaction((DatabaseExecutor txn) async {
      for (final String id in expenseIds) {
        await _tombstoneLive(txn, 'split_expenses', 'id = ?', id, now);
        final List<String> parts = await _liveIds(
          txn,
          'split_expense_parts',
          'split_expense_id = ?',
          id,
        );
        for (final String partId in parts) {
          await _tombstoneLive(
            txn,
            'split_expense_parts',
            'id = ?',
            partId,
            now,
          );
        }
      }
      for (final String table in <String>[
        'transactions',
        'contact_transactions',
      ]) {
        for (final String id in expenseIds) {
          final List<String> ids = await _liveIds(
            txn,
            table,
            'split_expense_id = ?',
            id,
          );
          for (final String rowId in ids) {
            await _tombstoneLive(txn, table, 'id = ?', rowId, now);
          }
        }
        for (final String id in settlementIds) {
          final List<String> ids = await _liveIds(
            txn,
            table,
            'split_settlement_id = ?',
            id,
          );
          for (final String rowId in ids) {
            await _tombstoneLive(txn, table, 'id = ?', rowId, now);
          }
        }
      }
      for (final String id in settlementIds) {
        await _tombstoneLive(txn, 'split_settlements', 'id = ?', id, now);
      }
      final List<String> memberIds = await _liveIds(
        txn,
        'split_group_members',
        'group_id = ?',
        groupId,
      );
      for (final String id in memberIds) {
        await _tombstoneLive(txn, 'split_group_members', 'id = ?', id, now);
      }
      await _tombstoneLive(txn, 'split_groups', 'id = ?', groupId, now);
    });
    _syncEngine?.notifyNewQueueItem();
  }

  /// Everything the group detail screen needs: header totals, balances and
  /// members.
  Future<SplitGroupDetail> getGroupDetail(String groupId) async {
    final AppDatabase database = _database;
    final SplitGroup group = await getGroup(groupId);
    final List<SplitMember> members = await getMembers(groupId);
    final GroupBalances balances = await _balancesOf(groupId);
    final List<Map<String, dynamic>> expenseRows = await database.db.query(
      'split_expenses',
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
    );
    final List<SplitExpense> expenses = expenseRows
        .map(SplitExpenseModel.fromJson)
        .toList();
    final String meId = SplitIds.member(groupId, null);
    final List<Map<String, dynamic>> myParts = await database.db.rawQuery(
      '''
      SELECT p.share_amount FROM split_expense_parts p
      JOIN split_expenses e ON e.id = p.split_expense_id
      WHERE e.group_id = ? AND e.deleted_at IS NULL
        AND p.member_id = ? AND p.deleted_at IS NULL
    ''',
      <Object>[groupId, meId],
    );
    final Decimal userShareTotal = myParts.fold(
      Decimal.zero,
      (Decimal sum, Map<String, dynamic> r) =>
          sum + Decimal.parse(r['share_amount'].toString()),
    );
    final Decimal totalSpent = expenses.fold(
      Decimal.zero,
      (Decimal sum, SplitExpense e) => sum + e.totalAmount,
    );
    return SplitGroupDetail(
      group: group,
      members: members,
      balances: balances,
      totalSpent: totalSpent,
      userShareTotal: userShareTotal,
    );
  }

  /// The group's expenses and settlements merged, newest first (ties by id),
  /// [limit] at a time.
  Future<List<SplitActivityItem>> getActivity(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> expenseRows = await database.db.query(
      'split_expenses',
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
    );
    final List<Map<String, dynamic>> settlementRows = await database.db.query(
      'split_settlements',
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
    );
    final String meId = SplitIds.member(groupId, null);
    final List<SplitActivityItem> items = <SplitActivityItem>[
      for (final Map<String, dynamic> row in expenseRows)
        SplitActivityExpense(
          expense: SplitExpenseModel.fromJson(row),
          userPart: await _userPartOf(row['id'] as String, meId),
        ),
      for (final Map<String, dynamic> row in settlementRows)
        SplitActivitySettlement(settlement: SplitSettlementModel.fromJson(row)),
    ];
    items.sort((SplitActivityItem a, SplitActivityItem b) {
      final int byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : _itemIdOf(a).compareTo(_itemIdOf(b));
    });
    if (offset >= items.length) return const <SplitActivityItem>[];
    final int end = (offset + limit).clamp(0, items.length);
    return items.sublist(offset, end);
  }

  String _itemIdOf(SplitActivityItem item) => switch (item) {
    SplitActivityExpense(:final SplitExpense expense) => expense.id,
    SplitActivitySettlement(:final SplitSettlement settlement) => settlement.id,
  };

  Future<SplitPart?> _userPartOf(String expenseId, String meId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'split_expense_parts',
      where: 'split_expense_id = ? AND member_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[expenseId, meId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SplitPartModel.fromJson(rows.first);
  }

  /// How much a group delete would remove: its live expenses and the live
  /// derived transactions and khata entries linked to them.
  Future<({int expenses, int khataEntries})> getGroupDeleteImpact(
    String groupId,
  ) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> expenses = await database.db.query(
      'split_expenses',
      columns: <String>['id'],
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
    );
    final List<String> expenseIds = <String>[
      for (final Map<String, dynamic> r in expenses) r['id'] as String,
    ];
    final List<Map<String, dynamic>> settlements = await database.db.query(
      'split_settlements',
      columns: <String>['id'],
      where: 'group_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[groupId],
    );
    final List<String> settlementIds = <String>[
      for (final Map<String, dynamic> r in settlements) r['id'] as String,
    ];
    int linked = 0;
    for (final String table in <String>[
      'transactions',
      'contact_transactions',
    ]) {
      for (final String column in <String>[
        'split_expense_id',
        'split_settlement_id',
      ]) {
        for (final List<String> ids in <List<String>>[
          expenseIds,
          settlementIds,
        ]) {
          if (ids.isEmpty) continue;
          final List<Map<String, dynamic>> rows = await database.db.query(
            table,
            columns: <String>['id'],
            where:
                '$column IN (${List<String>.filled(ids.length, '?').join(', ')}) AND deleted_at IS NULL',
            whereArgs: ids,
          );
          linked += rows.length;
        }
      }
    }
    return (expenses: expenseIds.length, khataEntries: linked);
  }

  Future<SplitSettlement?> _settlementOrNull(String settlementId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'split_settlements',
      where: 'id = ?',
      whereArgs: <Object>[settlementId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SplitSettlementModel.fromJson(rows.first);
  }

  /// Soft-deletes every live row of [table] matching [where].
  Future<void> _tombstoneLive(
    DatabaseExecutor txn,
    String table,
    String where,
    String id,
    DateTime now,
  ) async {
    final int updated = await txn.update(
      table,
      <String, dynamic>{
        'deleted_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
        'sync_status': 'pending',
      },
      where: '$where AND deleted_at IS NULL',
      whereArgs: <Object>[id],
    );
    if (updated == 0) return;
    await _enqueue(txn, SyncOperation.delete, table, id, tombstone(), now);
  }

  Future<List<String>> _liveIds(
    DatabaseExecutor txn,
    String table,
    String where,
    Object arg,
  ) async {
    final List<Map<String, dynamic>> rows = await txn.query(
      table,
      columns: <String>['id'],
      where: '$where AND deleted_at IS NULL',
      whereArgs: <Object>[arg],
    );
    return <String>[
      for (final Map<String, dynamic> r in rows) r['id'] as String,
    ];
  }

  Future<SplitExpense> _expenseRow(String expenseId) async {
    final SplitExpense? expense = await _expenseOrNull(expenseId);
    if (expense == null) throw const DatabaseFailure();
    return expense;
  }

  Future<SplitExpense?> _expenseOrNull(String expenseId) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'split_expenses',
      where: 'id = ?',
      whereArgs: <Object>[expenseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SplitExpenseModel.fromJson(rows.first);
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
