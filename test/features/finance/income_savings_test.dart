import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/savings_split.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';

SavingsGoal _goal(String id, String name) => SavingsGoal(
  id: id,
  userId: 'user-1',
  name: name,
  targetAmount: Decimal.parse('100000'),
  savedAmount: Decimal.zero,
  targetDate: null,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

SavingsPart _part(String goalId, String amount) =>
    (goalId: goalId, amount: Decimal.parse(amount));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFinance f;
  late TransactionController c;

  setUp(() {
    f = FakeFinance()..addAccount('Cash', '0');
    f.savingsGoals.addAll(<SavingsGoal>[
      _goal('g1', 'New phone'),
      _goal('g2', 'Trip'),
    ]);
    c = TransactionController(
      f.repositories.transactions,
      f.repositories.accounts,
      f.repositories.categories,
      DataChangeNotifier(),
      savingsGoals: f.repositories.savingsGoals,
    );
  });

  Future<bool> saveIncome({
    String id = 't1',
    Transaction? existing,
    TransactionType type = TransactionType.income,
    String amount = '50000',
    List<SavingsPart> savings = const <SavingsPart>[],
  }) => c.saveTransaction(
    id: id,
    existing: existing,
    type: type,
    amount: Decimal.parse(amount),
    accountId: 'acc-1',
    categoryId: null,
    date: DateTime(2026, 10, 24),
    note: null,
    savings: savings,
  );

  List<SavingsContribution> live() => f.contributions
      .where((SavingsContribution x) => x.deletedAt == null)
      .toList();

  Future<Map<String, Decimal>> totals() async => <String, Decimal>{
    for (final SavingsGoal g
        in await f.repositories.savingsGoals.getSavingsGoals())
      g.id: g.totalSaved,
  };

  test('saves an income with two goals and goal totals follow', () async {
    await c.loadLookups();
    expect(c.goals.map((SavingsGoal g) => g.id), <String>['g1', 'g2']);

    final bool ok = await saveIncome(
      savings: <SavingsPart>[_part('g1', '5000'), _part('g2', '3000')],
    );

    expect(ok, isTrue);
    expect(live(), hasLength(2));
    final Map<String, Decimal> sums = await totals();
    expect(sums['g1'], Decimal.parse('5000'));
    expect(sums['g2'], Decimal.parse('3000'));
  });

  test('saving the same new income twice keeps one row per goal', () async {
    final List<SavingsPart> parts = <SavingsPart>[
      _part('g1', '5000'),
      _part('g2', '3000'),
    ];

    // A retry after a failed receipt keeps the form's id and `existing: null`.
    expect(await saveIncome(savings: parts), isTrue);
    expect(await saveIncome(savings: parts), isTrue);

    expect(f.transactions, hasLength(1));
    expect(live(), hasLength(2));
    final Map<String, Decimal> sums = await totals();
    expect(sums['g1'], Decimal.parse('5000'));
    expect(sums['g2'], Decimal.parse('3000'));
  });

  test('refuses savings above the income', () async {
    final bool ok = await saveIncome(
      savings: <SavingsPart>[_part('g1', '60000')],
    );

    expect(ok, isFalse);
    expect(c.save.error.value, "Savings can't be more than the income");
    expect(f.transactions, isEmpty);
    expect(f.contributions, isEmpty);
  });

  test('editing the amount below its savings is refused', () async {
    await saveIncome(savings: <SavingsPart>[_part('g1', '8000')]);
    final Transaction stored = f.transactions.single;

    final bool ok = await saveIncome(
      existing: stored,
      amount: '5000',
      savings: <SavingsPart>[_part('g1', '8000')],
    );

    expect(ok, isFalse);
    expect(f.transactions.single.amount, Decimal.parse('50000'));
    expect(live().single.amount, Decimal.parse('8000'));
  });

  test('switching an income to expense drops its savings', () async {
    await saveIncome(savings: <SavingsPart>[_part('g1', '8000')]);
    final Transaction stored = f.transactions.single;

    final bool ok = await saveIncome(
      existing: stored,
      type: TransactionType.expense,
      savings: <SavingsPart>[_part('g1', '8000')],
    );

    expect(ok, isTrue);
    expect(f.transactions.single.type, TransactionType.expense);
    expect(live(), isEmpty);
  });

  test('edit keeps, changes and removes rows', () async {
    await saveIncome(
      savings: <SavingsPart>[_part('g1', '5000'), _part('g2', '3000')],
    );
    final Transaction stored = f.transactions.single;
    final SavingsContribution g1Row = live().firstWhere(
      (SavingsContribution x) => x.goalId == 'g1',
    );
    final SavingsContribution g2Row = live().firstWhere(
      (SavingsContribution x) => x.goalId == 'g2',
    );

    final bool ok = await saveIncome(
      existing: stored,
      savings: <SavingsPart>[_part('g1', '6000')],
    );

    expect(ok, isTrue);
    final SavingsContribution kept = live().single;
    expect(kept.id, g1Row.id);
    expect(kept.amount, Decimal.parse('6000'));
    expect(
      f.contributions
          .firstWhere((SavingsContribution x) => x.id == g2Row.id)
          .deletedAt,
      isNotNull,
    );
  });

  test('deleting the income lowers the goal totals', () async {
    await saveIncome(savings: <SavingsPart>[_part('g1', '5000')]);
    expect((await totals())['g1'], Decimal.parse('5000'));

    final bool ok = await c.deleteTransaction('t1');

    expect(ok, isTrue);
    expect((await totals())['g1'], Decimal.zero);
  });

  test('detail controller lists the income savings', () async {
    f.addTransaction(id: 't1', type: TransactionType.income, amount: '50000');
    int n = 0;
    await f.repositories.transactions.updateTransaction(
      f.transactions.single,
      savings: SavingsSplit.diff(
        transactionId: 't1',
        current: const <SavingsContribution>[],
        wanted: <SavingsPart>[_part('g1', '5000'), _part('g2', '3000')],
        newId: () => 'c-${n++}',
        now: DateTime(2026, 10, 24),
      ),
    );
    final TransactionDetailController d = TransactionDetailController(
      f.repositories.transactions,
      DataChangeNotifier(),
      't1',
    );

    await d.load();

    expect(d.savings, hasLength(2));
  });
}
