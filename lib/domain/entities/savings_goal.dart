import 'package:decimal/decimal.dart';

/// Money the user is putting aside for something. [savedAmount] is the
/// starting amount (set in the goal form); money added later by hand
/// ([addedAmount]) and from incomes ([contributedAmount]) adds to it. A goal
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
    Decimal? addedAmount,
  }) : contributedAmount = contributedAmount ?? Decimal.zero,
       addedAmount = addedAmount ?? Decimal.zero;

  final String id;
  final String userId;
  final String name;
  final Decimal targetAmount;
  final Decimal savedAmount;

  /// Sum of the income contributions to this goal; derived, never stored here.
  final Decimal contributedAmount;

  /// Sum of the money added by hand ("Add money"); derived, never stored here.
  final Decimal addedAmount;

  /// Optional calendar day (time of day is ignored) to reach the target by.
  final DateTime? targetDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Starting amount, plus added by hand, plus contributed from incomes.
  Decimal get totalSaved => savedAmount + addedAmount + contributedAmount;

  /// This goal once [amount] more is added by hand (the Add money preview).
  SavingsGoal afterAdding(Decimal amount) => SavingsGoal(
    id: id,
    userId: userId,
    name: name,
    targetAmount: targetAmount,
    savedAmount: savedAmount,
    targetDate: targetDate,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    contributedAmount: contributedAmount,
    addedAmount: addedAmount + amount,
  );

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
