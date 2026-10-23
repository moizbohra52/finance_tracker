import 'package:decimal/decimal.dart';

/// Money the user is putting aside for something. [savedAmount] is updated by
/// hand: a goal never moves money or changes an account balance.
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    required this.savedAmount,
    required this.targetDate,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String name;
  final Decimal targetAmount;
  final Decimal savedAmount;

  /// Optional calendar day (time of day is ignored) to reach the target by.
  final DateTime? targetDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isReached => savedAmount >= targetAmount;

  /// Still to save; zero once the target is reached.
  Decimal get remaining =>
      isReached ? Decimal.zero : targetAmount - savedAmount;

  /// Saved share of the target, from 0 to 1.
  double get progress {
    // A zero target can only come from an unchecked backup restore.
    if (targetAmount <= Decimal.zero) return 0;
    return (savedAmount / targetAmount)
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
