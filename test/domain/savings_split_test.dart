import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/savings_split.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String v) => Decimal.parse(v);

SavingsPart part(String goalId, String amount) =>
    (goalId: goalId, amount: d(amount));

SavingsContribution contribution(String id, String goalId, String amount) =>
    SavingsContribution(
      id: id,
      userId: 'u',
      transactionId: 't1',
      goalId: goalId,
      amount: d(amount),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

String? validateIncome(String amount, List<SavingsPart> parts) =>
    SavingsSplit.validate(
      type: TransactionType.income,
      amount: d(amount),
      parts: parts,
    );

void main() {
  group('SavingsSplit.validate', () {
    test('accepts parts that fit inside an income', () {
      expect(
        validateIncome('50000', [part('g1', '5000'), part('g2', '3000')]),
        isNull,
      );
    });

    test('accepts no parts on an expense', () {
      expect(
        SavingsSplit.validate(
          type: TransactionType.expense,
          amount: d('100'),
          parts: const [],
        ),
        isNull,
      );
    });

    test('rejects parts on anything but an income', () {
      expect(
        SavingsSplit.validate(
          type: TransactionType.expense,
          amount: d('100'),
          parts: [part('g1', '10')],
        ),
        'Only an income can go to savings',
      );
    });

    test('rejects a zero part', () {
      expect(
        validateIncome('100', [part('g1', '0')]),
        'Amount must be more than zero',
      );
    });

    test('rejects the same goal twice', () {
      expect(
        validateIncome('100', [part('g1', '10'), part('g1', '20')]),
        'This goal is already used',
      );
    });

    test('rejects parts totalling more than the income', () {
      expect(
        validateIncome('50000', [part('g1', '25000'), part('g2', '25000.01')]),
        "Savings can't be more than the income",
      );
    });

    test('adds parts as decimals, not doubles', () {
      expect(
        validateIncome('0.30', [part('g1', '0.10'), part('g2', '0.20')]),
        isNull,
      );
      expect(
        validateIncome('0.30', [part('g1', '0.10'), part('g2', '0.21')]),
        "Savings can't be more than the income",
      );
    });
  });

  group('SavingsSplit.diff', () {
    final DateTime now = DateTime(2026, 10, 24);

    SplitChanges diff(
      List<SavingsContribution> current,
      List<SavingsPart> wanted,
    ) => SavingsSplit.diff(
      transactionId: 't1',
      current: current,
      wanted: wanted,
      newId: () => 'new-id',
      now: now,
    );

    test(
      'updates a changed goal, inserts a new one, deletes a dropped one',
      () {
        final SavingsContribution c1 = contribution('c1', 'g1', '5000');
        final SavingsContribution c2 = contribution('c2', 'g2', '3000');

        final SplitChanges changes = diff(
          [c1, c2],
          [part('g1', '6000'), part('g3', '1000')],
        );

        expect(changes.updates, hasLength(1));
        expect(changes.updates.single.id, c1.id);
        expect(changes.updates.single.amount, d('6000'));
        expect(changes.updates.single.updatedAt, now);
        expect(changes.inserts, hasLength(1));
        final SavingsContribution added = changes.inserts.single;
        expect(added.goalId, 'g3');
        expect(added.transactionId, 't1');
        expect(added.id, 'new-id');
        expect(added.userId, '');
        expect(added.amount, d('1000'));
        expect(added.createdAt, now);
        expect(added.updatedAt, now);
        expect(changes.deletes, [c2.id]);
        expect(changes.isEmpty, isFalse);
      },
    );

    test('leaves an unchanged amount alone', () {
      final SplitChanges changes = diff(
        [contribution('c1', 'g1', '5000')],
        [part('g1', '5000')],
      );

      expect(changes.isEmpty, isTrue);
    });

    test('treats equal decimals with different scale as unchanged', () {
      final SplitChanges changes = diff(
        [contribution('c1', 'g1', '5000')],
        [part('g1', '5000.00')],
      );

      expect(changes.isEmpty, isTrue);
    });

    test('deletes every current row when nothing is wanted', () {
      final SplitChanges changes = diff([
        contribution('c1', 'g1', '5000'),
        contribution('c2', 'g2', '3000'),
      ], const []);

      expect(changes.deletes, ['c1', 'c2']);
      expect(changes.inserts, isEmpty);
      expect(changes.updates, isEmpty);
    });

    test('keeps the first of two rows for one goal and deletes the other', () {
      final SplitChanges changes = diff(
        [contribution('c1', 'g1', '5000'), contribution('c2', 'g1', '5000')],
        [part('g1', '5000')],
      );

      expect(changes.updates, isEmpty);
      expect(changes.inserts, isEmpty);
      expect(changes.deletes, ['c2']);
    });

    test('deletes every duplicate row when nothing is wanted', () {
      final SplitChanges changes = diff([
        contribution('c1', 'g1', '5000'),
        contribution('c2', 'g1', '7'),
      ], const []);

      expect(changes.deletes, ['c1', 'c2']);
      expect(changes.inserts, isEmpty);
      expect(changes.updates, isEmpty);
    });

    test('updates the first duplicate and deletes the rest', () {
      final SplitChanges changes = diff(
        [contribution('c1', 'g1', '5000'), contribution('c2', 'g1', '5000')],
        [part('g1', '6000')],
      );

      expect(changes.updates, hasLength(1));
      expect(changes.updates.single.id, 'c1');
      expect(changes.updates.single.amount, d('6000'));
      expect(changes.inserts, isEmpty);
      expect(changes.deletes, ['c2']);
    });
  });

  group('SavingsSplit.total', () {
    test('adds amounts as decimals, zero for none', () {
      expect(
        SavingsSplit.total([part('g1', '0.10'), part('g2', '0.20')]),
        d('0.3'),
      );
      expect(SavingsSplit.total(const []), Decimal.zero);
    });
  });

  group('SavingsSplit.sumByGoal', () {
    test('adds amounts per goal as decimals', () {
      expect(
        SavingsSplit.sumByGoal([
          contribution('c1', 'g1', '0.10'),
          contribution('c2', 'g1', '0.20'),
          contribution('c3', 'g2', '5'),
        ]),
        {'g1': d('0.3'), 'g2': d('5')},
      );
    });
  });
}
