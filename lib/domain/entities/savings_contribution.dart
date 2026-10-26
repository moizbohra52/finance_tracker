import 'package:decimal/decimal.dart';

/// Part of one income [transactionId] that the user put towards a savings
/// goal. It records the split only: no money moves and the income amount
/// never changes.
class SavingsContribution {
  const SavingsContribution({
    required this.id,
    required this.userId,
    required this.transactionId,
    required this.goalId,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String transactionId;
  final String goalId;
  final Decimal amount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  SavingsContribution copyWith({
    Decimal? amount,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => SavingsContribution(
    id: id,
    userId: userId,
    transactionId: transactionId,
    goalId: goalId,
    amount: amount ?? this.amount,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
