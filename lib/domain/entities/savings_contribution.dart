import 'package:decimal/decimal.dart';

/// Money put towards a savings goal: part of one income [transactionId], or,
/// with no income, money the user added by hand on [addedAt] (the goal's
/// "Add money"). It records the amount only: no money moves and the income
/// amount never changes.
class SavingsContribution {
  const SavingsContribution({
    required this.id,
    required this.userId,
    required this.transactionId,
    required this.goalId,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.addedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;

  /// The income this came from; null for money added by hand.
  final String? transactionId;
  final String goalId;

  /// When money added by hand was added; null for an income's part, which
  /// is dated by its income.
  final DateTime? addedAt;

  bool get isFromIncome => transactionId != null;
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
    addedAt: addedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

/// One line of a savings goal's history: a contribution with the day it
/// counts from and, for an income's part, the income's title.
class SavingsHistoryEntry {
  const SavingsHistoryEntry({
    required this.contribution,
    required this.date,
    this.incomeTitle,
  });

  final SavingsContribution contribution;

  /// When the money was added by hand, or the income's date.
  final DateTime date;

  /// The income's description or note; null when it has neither, and for
  /// money added by hand.
  final String? incomeTitle;
}
