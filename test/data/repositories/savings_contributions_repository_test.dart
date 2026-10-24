import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/savings_split.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Transaction _income() => Transaction(
  id: 't1',
  userId: 'u',
  accountId: 'acc-1',
  type: TransactionType.income,
  amount: Decimal.parse('10000'),
  transactionDate: DateTime(2026, 10, 24),
  createdAt: DateTime(2026, 10, 24),
  updatedAt: DateTime(2026, 10, 24),
);

SavingsContribution _contribution(String id, String goalId, String amount) =>
    SavingsContribution(
      id: id,
      userId: 'u',
      transactionId: 't1',
      goalId: goalId,
      amount: Decimal.parse(amount),
      createdAt: DateTime(2026, 10, 24),
      updatedAt: DateTime(2026, 10, 24),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TransactionRepository repo;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repo = TransactionRepository(
      SupabaseClient('https://dummy.supabase.co', 'dummy-anon-key'),
      database: database,
      syncEngine: SyncEngine(database: database),
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
}
