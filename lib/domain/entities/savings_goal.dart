import 'package:decimal/decimal.dart';

/// Money the user is putting aside for something. [savedAmount] is updated by
/// hand, and income contributions add to it through [contributedAmount]: a goal
/// never moves money or changes an account balance.
class SavingsGoal {
  SavingsGoal({
    required this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    required this.savedAmount,
    required this.targetDate,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    Decimal? contributedAmount,
  }) : contributedAmount = contributedAmount ?? Decimal.zero;

  final String id;
  final String userId;
  final String name;
  final Decimal targetAmount;
  final Decimal savedAmount;

  /// Sum of the income contributions to this goal; derived, never stored here.
  final Decimal contributedAmount;

  /// Optional calendar day (time of day is ignored) to reach the target by.
  final DateTime? targetDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Saved by hand plus contributed from incomes.
  Decimal get totalSaved => savedAmount + contributedAmount;

  bool get isReached => totalSaved >= targetAmount;

  /// Still to save; zero once the target is reached.
  Decimal get remaining => isReached ? Decimal.zero : targetAmount - totalSaved;

  /// Saved share of the target, from 0 to 1.
  double get progress {
    // A zero target can only come from an unchecked backup restore.
    if (targetAmount <= Decimal.zero) return 0;
    return (totalSaved / targetAmount)
        .toDecimal(scaleOnInfinitePrecision: 4)
        .toDouble()
        .clamp(0, 1);
  }

  /// The target date is inclusive, so a goal is overdue from the day after.
  bool isOverdue(DateTime now) {
    final DateTime? date = targetDate;
    return !isReached &&
        date != null &&
        DateTime(now.year, now.month, now.day).isAfter(date);
  }
}
