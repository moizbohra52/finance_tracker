import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_balances.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Decimal d(String v) => Decimal.parse(v);

  final DateTime now = DateTime(2026, 10, 26, 12);
  final SplitExpense dinner = SplitExpense(
    id: 'e1',
    userId: 'u',
    groupId: 'g1',
    title: 'Dinner',
    totalAmount: d('1200'),
    expenseDate: now,
    splitMode: SplitMode.equal,
    categoryId: 'c',
    accountId: 'a',
    createdAt: now,
    updatedAt: now,
  );

  SplitPart part(String memberId, String paid, String share) => SplitPart(
    id: 'p-$memberId',
    userId: 'u',
    splitExpenseId: 'e1',
    memberId: memberId,
    paidAmount: d(paid),
    shareAmount: d(share),
    createdAt: now,
    updatedAt: now,
  );

  final Map<String, List<SplitPart>> partsByExpense = {
    'e1': [
      part('me', '800', '300'),
      part('amit', '0', '300'),
      part('neha', '0', '300'),
      part('rahul', '400', '300'),
    ],
  };

  SplitSettlement settlement(
    String id,
    String from,
    String to,
    String amount,
  ) => SplitSettlement(
    id: id,
    userId: 'u',
    groupId: 'g1',
    fromMemberId: from,
    toMemberId: to,
    amount: d(amount),
    settledAt: now,
    createdAt: now,
    updatedAt: now,
  );

  test('the dinner of the spec: nets and pairs', () {
    final GroupBalances balances = SplitBalances.compute(
      meId: 'me',
      expenses: [dinner],
      partsByExpense: partsByExpense,
      settlements: const [],
    );
    expect(balances.memberNets, {
      'me': d('500'),
      'amit': d('-300'),
      'neha': d('-300'),
      'rahul': d('100'),
    });
    final Decimal netSum = balances.memberNets.values.fold(
      Decimal.zero,
      (Decimal a, Decimal b) => a + b,
    );
    expect(netSum, Decimal.zero);
    expect(
      balances.pairs
          .map((PairBalance p) => '${p.debtorMemberId}→${p.creditorMemberId}')
          .toList(),
      ['amit→me', 'neha→me', 'amit→rahul', 'neha→rahul', 'rahul→me'],
    );
    expect(balances.pairs.map((PairBalance p) => p.amount).toList(), [
      d('200'),
      d('200'),
      d('100'),
      d('100'),
      d('100'),
    ]);
    expect(balances.netOf('me'), d('500'));
    expect(balances.netOf('amit'), d('-300'));
  });

  test('a settlement removes the pair it settles', () {
    final GroupBalances balances = SplitBalances.compute(
      meId: 'me',
      expenses: [dinner],
      partsByExpense: partsByExpense,
      settlements: [settlement('s1', 'amit', 'me', '200')],
    );
    expect(
      balances.pairs
          .map(
            (PairBalance p) =>
                '${p.debtorMemberId}→${p.creditorMemberId} ${p.amount}',
          )
          .toList(),
      ['neha→me 200', 'amit→rahul 100', 'neha→rahul 100', 'rahul→me 100'],
    );
    expect(balances.netOf('amit'), d('-100'));
  });

  test('overpaying a settlement flips the pair', () {
    final GroupBalances balances = SplitBalances.compute(
      meId: 'me',
      expenses: [dinner],
      partsByExpense: partsByExpense,
      settlements: [settlement('s1', 'amit', 'me', '250')],
    );
    expect(
      balances.pairs
          .map(
            (PairBalance p) =>
                '${p.debtorMemberId}→${p.creditorMemberId} ${p.amount}',
          )
          .toList(),
      [
        'neha→me 200',
        'amit→rahul 100',
        'neha→rahul 100',
        'rahul→me 100',
        'me→amit 50',
      ],
    );
    expect(balances.netOf('amit'), d('-50'));
  });

  test('a settlement between two friends only moves that pair', () {
    final GroupBalances balances = SplitBalances.compute(
      meId: 'me',
      expenses: [dinner],
      partsByExpense: partsByExpense,
      settlements: [settlement('s1', 'amit', 'rahul', '100')],
    );
    expect(balances.netOf('amit'), d('-200'));
    expect(balances.netOf('rahul'), d('0'));
    expect(
      balances.pairs
          .map(
            (PairBalance p) =>
                '${p.debtorMemberId}→${p.creditorMemberId} ${p.amount}',
          )
          .toList(),
      ['amit→me 200', 'neha→me 200', 'neha→rahul 100', 'rahul→me 100'],
    );
  });

  test('an empty group has no nets and no pairs', () {
    final GroupBalances balances = SplitBalances.compute(
      meId: 'me',
      expenses: const [],
      partsByExpense: const {},
      settlements: const [],
    );
    expect(balances.memberNets, isEmpty);
    expect(balances.pairs, isEmpty);
    expect(balances.netOf('me'), Decimal.zero);
  });

  test('deleted rows are ignored', () {
    final SplitExpense deleted = SplitExpense(
      id: 'e2',
      userId: 'u',
      groupId: 'g1',
      title: 'Old',
      totalAmount: d('500'),
      expenseDate: now,
      splitMode: SplitMode.equal,
      categoryId: 'c',
      accountId: 'a',
      createdAt: now,
      updatedAt: now,
      deletedAt: now,
    );
    final SplitPart deadPart = part(
      'amit',
      '500',
      '0',
    ).copyWith(deletedAt: now);
    final SplitSettlement dead = settlement(
      's2',
      'amit',
      'me',
      '100',
    ).copyWith(deletedAt: now);
    final GroupBalances balances = SplitBalances.compute(
      meId: 'me',
      expenses: [dinner, deleted],
      partsByExpense: {
        ...partsByExpense,
        'e2': [deadPart],
      },
      settlements: [settlement('s1', 'amit', 'me', '200'), dead],
    );
    expect(
      balances.pairs
          .map(
            (PairBalance p) =>
                '${p.debtorMemberId}→${p.creditorMemberId} ${p.amount}',
          )
          .toList(),
      ['neha→me 200', 'amit→rahul 100', 'neha→rahul 100', 'rahul→me 100'],
    );
  });
}
