import 'package:decimal/decimal.dart';
import 'package:finance_tracker/data/models/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime created = DateTime.utc(2026, 10, 24, 9);
  final DateTime updated = DateTime.utc(2026, 10, 24, 10);

  Map<String, dynamic> row({Object amount = '1500.50'}) => <String, dynamic>{
    'id': 'c1',
    'user_id': 'u1',
    'transaction_id': 't1',
    'goal_id': 'g1',
    'amount': amount,
    'created_at': created.toIso8601String(),
    'updated_at': updated.toIso8601String(),
    'deleted_at': null,
  };

  test('fromJson reads a row and toJson writes it back', () {
    final SavingsContribution c = SavingsContributionModel.fromJson(row());

    expect(c.id, 'c1');
    expect(c.userId, 'u1');
    expect(c.transactionId, 't1');
    expect(c.goalId, 'g1');
    expect(c.amount, Decimal.parse('1500.50'));
    expect(c.createdAt, created);
    expect(c.updatedAt, updated);
    expect(c.deletedAt, isNull);

    expect(SavingsContributionModel.toJson(c), <String, dynamic>{
      'id': 'c1',
      'user_id': 'u1',
      'transaction_id': 't1',
      'goal_id': 'g1',
      'amount': '1500.5',
    });
  });

  test('fromJson accepts a numeric amount', () {
    final SavingsContribution c = SavingsContributionModel.fromJson(
      row(amount: 1500.5),
    );

    expect(c.amount, Decimal.parse('1500.5'));
  });

  test('fromJson reads deleted_at', () {
    final SavingsContribution c = SavingsContributionModel.fromJson(
      <String, dynamic>{...row(), 'deleted_at': updated.toIso8601String()},
    );

    expect(c.deletedAt, updated);
  });

  test('toJson has no timestamps', () {
    final Map<String, dynamic> json = SavingsContributionModel.toJson(
      SavingsContributionModel.fromJson(row()),
    );

    expect(json.containsKey('created_at'), isFalse);
    expect(json.containsKey('updated_at'), isFalse);
    expect(json.containsKey('deleted_at'), isFalse);
  });
}
