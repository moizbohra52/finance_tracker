import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/savings_goal_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/savings_split.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Transaction _income({String id = 't1'}) => Transaction(
  id: id,
  userId: 'u',
  accountId: 'acc-1',
  type: TransactionType.income,
  amount: Decimal.parse('10000'),
  transactionDate: DateTime(2026, 10, 24),
  createdAt: DateTime(2026, 10, 24),
  updatedAt: DateTime(2026, 10, 24),
);

SavingsContribution _contribution(
  String id,
  String goalId,
  String amount, {
  String transactionId = 't1',
}) => SavingsContribution(
  id: id,
  userId: 'u',
  transactionId: transactionId,
  goalId: goalId,
  amount: Decimal.parse(amount),
  createdAt: DateTime(2026, 10, 24),
  updatedAt: DateTime(2026, 10, 24),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TransactionRepository repo;
  late SavingsGoalRepository goals;

  setUp(() async {
    database = await AppDatabase.inMemory();
    final SupabaseClient client = SupabaseClient(
      'https://dummy.supabase.co',
      'dummy-anon-key',
    );
    final SyncEngine engine = SyncEngine(database: database);
    repo = TransactionRepository(
      client,
      database: database,
      syncEngine: engine,
    );
    goals = SavingsGoalRepository(
      client,
      database: database,
      syncEngine: engine,
    );
  });

  tearDown(() => database.close());

  Future<List<(SyncOperation, String)>> queue() async =>
      <(SyncOperation, String)>[
        for (final SyncQueueItem i in await database.getPendingQueue())
          (i.operation, i.entity),
      ];

  test(
    'create writes the income and its contributions, queued in that order',
    () async {
      await repo.createTransaction(
        _income(),
        contributions: <SavingsContribution>[
          _contribution('c1', 'g1', '5000'),
          _contribution('c2', 'g2', '2000'),
        ],
      );

      expect(await queue(), <(SyncOperation, String)>[
        (SyncOperation.create, 'transactions'),
        (SyncOperation.create, 'savings_contributions'),
        (SyncOperation.create, 'savings_contributions'),
      ]);
      final List<SavingsContribution> stored = await repo.getContributions(
        't1',
      );
      expect(stored.map((SavingsContribution c) => c.id), <String>['c1', 'c2']);
      expect(stored.first.amount, Decimal.parse('5000'));
    },
  );

  test('a failure while writing contributions leaves nothing behind', () async {
    await database.db.execute('DROP TABLE savings_contributions');

    await expectLater(
      repo.createTransaction(
        _income(),
        contributions: <SavingsContribution>[_contribution('c1', 'g1', '5000')],
      ),
      throwsA(anything),
    );

    expect(
      await database.db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object>['t1'],
      ),
      isEmpty,
    );
    expect(await queue(), isEmpty);
  });

  test('update applies inserts, updates and deletes', () async {
    final SavingsContribution c1 = _contribution('c1', 'g1', '5000');
    final SavingsContribution c2 = _contribution('c2', 'g2', '2000');
    await repo.createTransaction(
      _income(),
      contributions: <SavingsContribution>[c1, c2],
    );

    await repo.updateTransaction(
      _income(),
      savings: SplitChanges(
        inserts: <SavingsContribution>[_contribution('c3', 'g3', '1000')],
        updates: <SavingsContribution>[
          c1.copyWith(amount: Decimal.parse('6000')),
        ],
        deletes: <String>[c2.id],
      ),
    );

    final List<SavingsContribution> live = await repo.getContributions('t1');
    expect(live.map((SavingsContribution c) => c.id).toSet(), <String>{
      'c1',
      'c3',
    });
    expect(
      live.firstWhere((SavingsContribution c) => c.id == 'c1').amount,
      Decimal.parse('6000'),
    );
    expect((await queue()).skip(3).toList(), <(SyncOperation, String)>[
      (SyncOperation.update, 'transactions'),
      (SyncOperation.create, 'savings_contributions'),
      (SyncOperation.update, 'savings_contributions'),
      (SyncOperation.delete, 'savings_contributions'),
    ]);
  });

  test(
    'deleting the income soft-deletes its contributions and queues them',
    () async {
      await repo.createTransaction(
        _income(),
        contributions: <SavingsContribution>[
          _contribution('c1', 'g1', '5000'),
          _contribution('c2', 'g2', '2000'),
        ],
      );

      await repo.deleteTransaction('t1');

      expect(await repo.getContributions('t1'), isEmpty);
      final List<Map<String, Object?>> raw = await database.db.query(
        'savings_contributions',
      );
      expect(raw, hasLength(2));
      expect(
        raw.every((Map<String, Object?> r) => r['deleted_at'] != null),
        true,
      );
      expect((await queue()).skip(3).toList(), <(SyncOperation, String)>[
        (SyncOperation.delete, 'transactions'),
        (SyncOperation.delete, 'savings_contributions'),
        (SyncOperation.delete, 'savings_contributions'),
      ]);
    },
  );

  Future<void> createGoal() => goals.createSavingsGoal(
    SavingsGoal(
      id: 'g1',
      userId: 'u',
      name: 'Bike',
      targetAmount: Decimal.parse('20000'),
      savedAmount: Decimal.parse('100'),
      targetDate: null,
      createdAt: DateTime(2026, 10, 24),
      updatedAt: DateTime(2026, 10, 24),
    ),
  );

  test('goal totals add live contributions only', () async {
    await createGoal();
    await repo.createTransaction(
      _income(),
      contributions: <SavingsContribution>[_contribution('c1', 'g1', '5000')],
    );
    await repo.createTransaction(
      _income(id: 't2'),
      contributions: <SavingsContribution>[
        _contribution('c2', 'g1', '0.10', transactionId: 't2'),
      ],
    );
    await repo.deleteTransaction('t2');
    // Sync race: the income tombstone arrives before its contribution's, so
    // only the transaction predicate can exclude c2.
    await database.db.update(
      'savings_contributions',
      <String, dynamic>{'deleted_at': null},
      where: 'id = ?',
      whereArgs: <Object>['c2'],
    );
    // No API writes a contribution without its transaction, so this orphan
    // (t9 is not stored locally) goes in raw: the JOIN must drop it.
    await database.db.insert('savings_contributions', <String, dynamic>{
      'id': 'c3',
      'user_id': 'u',
      'transaction_id': 't9',
      'goal_id': 'g1',
      'amount': '7',
      'created_at': DateTime(2026, 10, 24).toIso8601String(),
      'updated_at': DateTime(2026, 10, 24).toIso8601String(),
      'sync_status': 'synced',
    });

    final SavingsGoal goal = (await goals.getSavingsGoals()).single;

    expect(goal.contributedAmount, Decimal.parse('5000'));
    expect(goal.totalSaved, Decimal.parse('5100'));
  });

  test('deleting a goal soft-deletes its contributions', () async {
    await createGoal();
    await repo.createTransaction(
      _income(),
      contributions: <SavingsContribution>[_contribution('c1', 'g1', '5000')],
    );

    await goals.deleteSavingsGoal('g1');

    expect(await repo.getContributions('t1'), isEmpty);
    expect(await goals.getSavingsGoals(), isEmpty);
    expect(
      await queue(),
      contains((SyncOperation.delete, 'savings_contributions')),
    );
  });

  group('money added by hand', () {
    SavingsContribution added(String id, String amount, DateTime at) =>
        SavingsContribution(
          id: id,
          userId: 'u',
          transactionId: null,
          goalId: 'g1',
          amount: Decimal.parse(amount),
          addedAt: at,
          createdAt: at,
          updatedAt: at,
        );

    test('is stored without an income, queued once per id, and summed '
        'apart from incomes', () async {
      await createGoal();
      await repo.createTransaction(
        _income(),
        contributions: <SavingsContribution>[_contribution('c1', 'g1', '5000')],
      );
      final SavingsContribution m1 = added('m1', '300', DateTime(2026, 10, 25));
      await goals.addMoney(m1);
      await goals.addMoney(m1); // A retried save upserts the same row.

      final SavingsGoal goal = (await goals.getSavingsGoals()).single;
      expect(goal.savedAmount, Decimal.parse('100'));
      expect(goal.addedAmount, Decimal.parse('300'));
      expect(goal.contributedAmount, Decimal.parse('5000'));
      expect(goal.totalSaved, Decimal.parse('5400'));

      final List<Map<String, Object?>> rows = await database.db.query(
        'savings_contributions',
        where: 'id = ?',
        whereArgs: <Object>['m1'],
      );
      expect(rows.single['transaction_id'], isNull);
      final SyncQueueItem item = (await database.getPendingQueue()).lastWhere(
        (SyncQueueItem i) => i.entityId == 'm1',
      );
      expect(item.operation, SyncOperation.create);
      expect(item.payload['transaction_id'], isNull);
      expect(
        DateTime.parse(
          item.payload['added_at'] as String,
        ).isAtSameMomentAs(DateTime(2026, 10, 25)),
        isTrue,
      );
    });

    test('history lists both kinds newest first, in pages', () async {
      await createGoal();
      await repo.createTransaction(
        _income(),
        contributions: <SavingsContribution>[_contribution('c1', 'g1', '5000')],
      );
      await goals.addMoney(added('m1', '300', DateTime(2026, 10, 25, 9)));
      await goals.addMoney(added('m2', '50', DateTime(2026, 10, 23)));

      final List<SavingsHistoryEntry> all = await goals.getHistory('g1');
      expect(all.map((SavingsHistoryEntry e) => e.contribution.id), <String>[
        'm1',
        'c1',
        'm2',
      ]);
      expect(all[1].contribution.isFromIncome, isTrue);
      expect(all[1].date, DateTime(2026, 10, 24));
      expect(all[0].date, DateTime(2026, 10, 25, 9));

      final List<SavingsHistoryEntry> first = await goals.getHistory(
        'g1',
        limit: 2,
      );
      final List<SavingsHistoryEntry> rest = await goals.getHistory(
        'g1',
        offset: 2,
        limit: 2,
      );
      expect(
        <String>[
          for (final SavingsHistoryEntry e in <SavingsHistoryEntry>[
            ...first,
            ...rest,
          ])
            e.contribution.id,
        ],
        <String>['m1', 'c1', 'm2'],
      );
    });

    test('deleteContribution removes money added by hand, never the part '
        'of an income', () async {
      await createGoal();
      await repo.createTransaction(
        _income(),
        contributions: <SavingsContribution>[_contribution('c1', 'g1', '5000')],
      );
      await goals.addMoney(added('m1', '300', DateTime(2026, 10, 25)));

      await goals.deleteContribution('m1');
      await goals.deleteContribution('c1');

      expect(
        (await goals.getHistory(
          'g1',
        )).map((SavingsHistoryEntry e) => e.contribution.id),
        <String>['c1'],
      );
      expect((await goals.getSavingsGoals()).single.addedAmount, Decimal.zero);
      final List<SyncQueueItem> deletes = <SyncQueueItem>[
        for (final SyncQueueItem i in await database.getPendingQueue())
          if (i.operation == SyncOperation.delete) i,
      ];
      expect(deletes.map((SyncQueueItem i) => i.entityId), <String>['m1']);
    });

    test('deleting the goal removes its money added by hand too', () async {
      await createGoal();
      await goals.addMoney(added('m1', '300', DateTime(2026, 10, 25)));

      await goals.deleteSavingsGoal('g1');

      expect(await goals.getHistory('g1'), isEmpty);
    });
  });
}
