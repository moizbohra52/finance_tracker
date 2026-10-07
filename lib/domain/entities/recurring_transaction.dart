import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';

enum RecurringFrequency {
  daily('day', 'Daily'),
  weekly('week', 'Weekly'),
  monthly('month', 'Monthly'),
  yearly('year', 'Yearly');

  const RecurringFrequency(this.unit, this.label);

  /// Singular unit word, for "every 2 weeks".
  final String unit;
  final String label;
}

/// An income or expense that repeats on a schedule. The schedule is every
/// [intervalCount] x [frequency] (so "every 2 weeks" is weekly with 2).
class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.categoryId,
    required this.type,
    required this.amount,
    required this.frequency,
    required this.intervalCount,
    required this.startDate,
    required this.endDate,
    required this.nextRunAt,
    required this.active,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String accountId;
  final String? categoryId;

  /// Only [TransactionType.income] or [TransactionType.expense].
  final TransactionType type;
  final Decimal amount;
  final RecurringFrequency frequency;
  final int intervalCount;

  /// Calendar days. [endDate] is inclusive.
  final DateTime startDate;
  final DateTime? endDate;

  /// The next occurrence that has not been turned into a transaction yet.
  final DateTime nextRunAt;
  final bool active;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// "Daily", "Weekly", or "Every 2 weeks".
  String get scheduleLabel => intervalCount == 1
      ? frequency.label
      : 'Every $intervalCount ${frequency.unit}s';

  RecurringTransaction copyWith({
    String? accountId,
    String? categoryId,
    bool clearCategory = false,
    TransactionType? type,
    Decimal? amount,
    RecurringFrequency? frequency,
    int? intervalCount,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    DateTime? nextRunAt,
    bool? active,
    String? note,
    bool clearNote = false,
  }) => RecurringTransaction(
    id: id,
    userId: userId,
    accountId: accountId ?? this.accountId,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    type: type ?? this.type,
    amount: amount ?? this.amount,
    frequency: frequency ?? this.frequency,
    intervalCount: intervalCount ?? this.intervalCount,
    startDate: startDate ?? this.startDate,
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
    nextRunAt: nextRunAt ?? this.nextRunAt,
    active: active ?? this.active,
    note: clearNote ? null : (note ?? this.note),
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    deletedAt: deletedAt,
  );
}
