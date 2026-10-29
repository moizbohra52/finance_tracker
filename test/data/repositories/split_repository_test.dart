import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/contact_transaction.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
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

  group('expenses and their derived rows', () {
    const String groupId = 'g-dinner';
    const String accountId = 'acc-1';
    final DateTime date = DateTime(2026, 10, 26, 19, 30);
    late String meId;
    late String amitId;
    late String nehaId;
    late String rahulId;

    Future<void> seedGroup() async {
      await repo.saveGroup(
        groupId: groupId,
        name: 'Goa',
        friendContactIds: <String>['c-amit', 'c-neha', 'c-rahul'],
      );
      meId = SplitIds.member(groupId, null);
      amitId = SplitIds.member(groupId, 'c-amit');
      nehaId = SplitIds.member(groupId, 'c-neha');
      rahulId = SplitIds.member(groupId, 'c-rahul');
    }

    SplitExpense expenseEntity({
      String id = 'e1',
      String total = '1200',
      String? categoryId = 'cat-1',
      SplitMode mode = SplitMode.equal,
    }) => SplitExpense(
      id: id,
      userId: '',
      groupId: groupId,
      title: 'Dinner',
      totalAmount: Decimal.parse(total),
      expenseDate: date,
      splitMode: mode,
      categoryId: categoryId,
      accountId: accountId,
      createdAt: now,
      updatedAt: now,
    );

    SplitPart part(String memberId, String paid, String share) => SplitPart(
      id: '',
      userId: '',
      splitExpenseId: 'e1',
      memberId: memberId,
      paidAmount: Decimal.parse(paid),
      shareAmount: Decimal.parse(share),
      createdAt: now,
      updatedAt: now,
    );

    Future<List<Transaction>> liveTransactions() async {
      final List<Map<String, dynamic>> rows = await database.db.query(
        'transactions',
        where: 'split_expense_id = ? AND deleted_at IS NULL',
        whereArgs: <Object>['e1'],
      );
      return rows
          .map(TransactionModel.fromJson)
          .map((TransactionModel m) => m.toEntity())
          .toList();
    }

    Future<List<ContactTransaction>> liveKhata() async {
      final List<Map<String, dynamic>> rows = await database.db.query(
        'contact_transactions',
        where: 'split_expense_id = ? AND deleted_at IS NULL',
        whereArgs: <Object>['e1'],
      );
      return rows
          .map(ContactTransactionModel.fromJson)
          .map((ContactTransactionModel m) => m.toEntity())
          .toList();
    }

    test(
      'the dinner of the spec writes the derived rows parent-first',
      () async {
        await seedGroup();
        await repo.saveExpense(
          expense: expenseEntity(),
          parts: <SplitPart>[
            part(meId, '800', '300'),
            part(amitId, '0', '300'),
            part(nehaId, '0', '300'),
            part(rahulId, '400', '300'),
          ],
        );

        final List<Transaction> txns = await liveTransactions();
        expect(txns.length, 2);
        final Transaction share = txns.singleWhere(
          (Transaction t) => t.id == SplitIds.expenseShare('e1'),
        );
        expect(share.type, TransactionType.expense);
        expect(share.amount, Decimal.parse('300'));
        expect(share.categoryId, 'cat-1');
        expect(share.accountId, accountId);
        final Transaction balance = txns.singleWhere(
          (Transaction t) => t.id == SplitIds.expenseBalance('e1'),
        );
        expect(balance.type, TransactionType.payment_made);
        expect(balance.amount, Decimal.parse('500'));
        expect(balance.contactId, isNull);

        final List<ContactTransaction> khata = await liveKhata();
        expect(khata.length, 3);
        final Map<String, ContactTransaction> byContact =
            <String, ContactTransaction>{
              for (final ContactTransaction c in khata) c.contactId: c,
            };
        expect(byContact['c-amit']!.type, ContactTransactionType.credit);
        expect(byContact['c-amit']!.amount, Decimal.parse('200'));
        expect(byContact['c-neha']!.type, ContactTransactionType.credit);
        expect(byContact['c-neha']!.amount, Decimal.parse('200'));
        expect(byContact['c-rahul']!.type, ContactTransactionType.credit);
        expect(byContact['c-rahul']!.amount, Decimal.parse('100'));

        // The saveGroup items are already queued; this save adds ten more.
        final List<SyncQueueItem> all = await queue();
        final List<SyncQueueItem> items = all.sublist(all.length - 10);
        final List<String> entities = items
            .map((SyncQueueItem i) => i.entity)
            .toList();
        expect(entities, <String>[
          'split_expenses',
          'split_expense_parts',
          'split_expense_parts',
          'split_expense_parts',
          'split_expense_parts',
          'transactions',
          'transactions',
          'contact_transactions',
          'contact_transactions',
          'contact_transactions',
        ]);
      },
    );

    test('a friend who paid everything: the user owes their share', () async {
      await seedGroup();
      await repo.saveExpense(
        expense: expenseEntity(),
        parts: <SplitPart>[
          part(meId, '0', '300'),
          part(amitId, '0', '300'),
          part(nehaId, '0', '300'),
          part(rahulId, '1200', '300'),
        ],
      );

      final List<Transaction> txns = await liveTransactions();
      expect(txns.length, 2);
      expect(
        txns
            .singleWhere(
              (Transaction t) => t.id == SplitIds.expenseBalance('e1'),
            )
            .type,
        TransactionType.payment_received,
      );
      final List<ContactTransaction> khata = await liveKhata();
      expect(khata.length, 1);
      expect(khata.single.contactId, 'c-rahul');
      expect(khata.single.type, ContactTransactionType.debit);
      expect(khata.single.amount, Decimal.parse('300'));
    });

    test('a retry with the same ids adds no duplicate live rows', () async {
      await seedGroup();
      final SplitExpense expense = expenseEntity();
      final List<SplitPart> parts = <SplitPart>[
        part(meId, '800', '300'),
        part(amitId, '0', '300'),
        part(nehaId, '0', '300'),
        part(rahulId, '400', '300'),
      ];
      await repo.saveExpense(expense: expense, parts: parts);
      final List<SyncQueueItem> itemsBefore = await queue();
      final int liveTxnsBefore = (await liveTransactions()).length;
      final int liveKhataBefore = (await liveKhata()).length;

      await repo.saveExpense(expense: expense, parts: parts);

      expect((await liveTransactions()).length, liveTxnsBefore);
      expect((await liveKhata()).length, liveKhataBefore);
      final List<SyncQueueItem> added = (await queue()).sublist(
        itemsBefore.length,
      );
      expect(added, isNotEmpty);
      expect(
        added.every((SyncQueueItem i) => i.operation == SyncOperation.update),
        isTrue,
        reason: 'a retry only queues updates',
      );
    });

    test('a role flip changes the balance row in place', () async {
      await seedGroup();
      await repo.saveExpense(
        expense: expenseEntity(),
        parts: <SplitPart>[
          part(meId, '800', '300'),
          part(amitId, '0', '300'),
          part(nehaId, '0', '300'),
          part(rahulId, '400', '300'),
        ],
      );
      final String balanceId = SplitIds.expenseBalance('e1');
      final String rahulKhataId = SplitIds.expenseContact('e1', 'c-rahul');

      // Rahul paid everything now: the user's role flipped.
      await repo.saveExpense(
        expense: expenseEntity(),
        parts: <SplitPart>[
          part(meId, '0', '300'),
          part(amitId, '0', '300'),
          part(nehaId, '0', '300'),
          part(rahulId, '1200', '300'),
        ],
      );

      final List<Transaction> txns = await liveTransactions();
      expect(txns.length, 2, reason: 'no stale derived row remains');
      final Transaction balance = txns.singleWhere(
        (Transaction t) => t.id == balanceId,
      );
      expect(balance.type, TransactionType.payment_received);
      expect(balance.amount, Decimal.parse('300'));

      final List<ContactTransaction> khata = await liveKhata();
      final ContactTransaction rahul = khata.singleWhere(
        (ContactTransaction c) => c.contactId == 'c-rahul',
      );
      expect(rahul.id, rahulKhataId);
      expect(rahul.type, ContactTransactionType.debit);
      expect(rahul.amount, Decimal.parse('300'));
    });

    test('a removed part tombstones its row and khata entry', () async {
      await seedGroup();
      await repo.saveExpense(
        expense: expenseEntity(),
        parts: <SplitPart>[
          part(meId, '800', '300'),
          part(amitId, '0', '300'),
          part(nehaId, '0', '300'),
          part(rahulId, '400', '300'),
        ],
      );

      await repo.saveExpense(
        expense: expenseEntity(),
        parts: <SplitPart>[
          part(meId, '800', '400'),
          part(amitId, '0', '400'),
          part(rahulId, '400', '400'),
        ],
      );

      final List<Map<String, dynamic>> partRows = await database.db.query(
        'split_expense_parts',
        where: 'split_expense_id = ? AND deleted_at IS NULL',
        whereArgs: <Object>['e1'],
      );
      expect(partRows.length, 3, reason: 'at most one live row per member');
      final List<ContactTransaction> khata = await liveKhata();
      expect(
        khata.where((ContactTransaction c) => c.contactId == 'c-neha'),
        isEmpty,
      );
    });

    test('a user who only paid for others needs no category', () async {
      await seedGroup();
      await repo.saveExpense(
        expense: expenseEntity(categoryId: null, total: '600'),
        parts: <SplitPart>[part(meId, '600', '0'), part(amitId, '0', '600')],
      );

      final List<Transaction> txns = await liveTransactions();
      expect(
        txns.any((Transaction t) => t.id == SplitIds.expenseShare('e1')),
        isFalse,
      );
      final Transaction balance = txns.single;
      expect(balance.type, TransactionType.payment_made);
      expect(balance.amount, Decimal.parse('600'));
      expect((await liveKhata()).single.amount, Decimal.parse('600'));
    });

    test('invalid input throws and writes nothing', () async {
      await seedGroup();
      final int queueBefore = (await queue()).length;
      await expectLater(
        repo.saveExpense(
          expense: expenseEntity(),
          parts: <SplitPart>[
            part(meId, '799.99', '300'),
            part(amitId, '0', '300'),
            part(nehaId, '0', '300'),
            part(rahulId, '400', '300'),
          ],
        ),
        throwsA(
          isA<UnexpectedFailure>().having(
            (UnexpectedFailure e) => e.message,
            'message',
            'What was paid must add up to the total',
          ),
        ),
      );
      expect((await queue()).length, queueBefore);
      final List<Map<String, Object?>> expenses = await database.db.query(
        'split_expenses',
      );
      expect(expenses, isEmpty);
    });

    test('a failure inside the transaction leaves nothing behind', () async {
      await seedGroup();
      final int queueBefore = (await queue()).length;
      await database.db.execute('DROP TABLE split_expense_parts');
      await expectLater(
        repo.saveExpense(
          expense: expenseEntity(),
          parts: <SplitPart>[
            part(meId, '800', '300'),
            part(amitId, '0', '300'),
            part(nehaId, '0', '300'),
            part(rahulId, '400', '300'),
          ],
        ),
        throwsA(isA<Exception>()),
      );
      final List<Map<String, Object?>> expenses = await database.db.query(
        'split_expenses',
      );
      expect(expenses, isEmpty, reason: 'the transaction rolled back');
      expect((await queue()).length, queueBefore);
    });

    test('deleteExpense tombstones everything it owns', () async {
      await seedGroup();
      await repo.saveExpense(
        expense: expenseEntity(),
        parts: <SplitPart>[
          part(meId, '800', '300'),
          part(amitId, '0', '300'),
          part(nehaId, '0', '300'),
          part(rahulId, '400', '300'),
        ],
      );
      final Account account = Account(
        id: accountId,
        userId: '',
        name: 'Bank',
        type: AccountType.bank,
        openingBalance: Decimal.parse('10000'),
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
      final Contact amit = Contact(
        id: 'c-amit',
        userId: '',
        name: 'Amit',
        openingBalance: Decimal.zero,
        openingBalanceType: 'receivable',
        createdAt: now,
        updatedAt: now,
      );
      Future<Decimal> accountBalance() async {
        final List<Map<String, dynamic>> rows = await database.db.query(
          'transactions',
        );
        final List<Transaction> transactions = rows
            .map(TransactionModel.fromJson)
            .map((TransactionModel m) => m.toEntity())
            .toList();
        return FinanceSummaryCalculator.accountBalances(<Account>[
          account,
        ], transactions)[accountId]!;
      }

      final Decimal balanceAfterExpense = await accountBalance();
      expect(balanceAfterExpense, Decimal.parse('9200'));

      await repo.deleteExpense('e1');

      expect((await liveTransactions()), isEmpty);
      expect((await liveKhata()), isEmpty);
      final List<Map<String, Object?>> expenses = await database.db.query(
        'split_expenses',
        where: 'deleted_at IS NULL',
      );
      expect(expenses, isEmpty);
      expect(
        (await queue())
            .where((SyncQueueItem i) => i.operation == SyncOperation.delete)
            .length,
        10,
        reason: 'expense + 4 parts + 2 transactions + 3 khata rows',
      );
      final Decimal balanceAfterDelete = await accountBalance();
      expect(balanceAfterDelete, Decimal.parse('10000'));
      final List<Map<String, dynamic>> khataRows = await database.db.query(
        'contact_transactions',
        where: 'contact_id = ?',
        whereArgs: <Object>['c-amit'],
      );
      final List<ContactTransaction> amitKhata = khataRows
          .map(ContactTransactionModel.fromJson)
          .map((ContactTransactionModel m) => m.toEntity())
          .toList();
      expect(amit.getCurrentBalance(amitKhata), Decimal.zero);
    });
  });
}
