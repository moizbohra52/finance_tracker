import 'package:decimal/decimal.dart';

enum BudgetPeriodType { monthly, custom }

/// A spending limit. A null [categoryId] covers all expense categories.
class Budget {
  const Budget({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.amount,
    required this.periodType,
    required this.startDate,
    required this.endDate,
    required this.alert75,
    required this.alert90,
    required this.alert100,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String? categoryId;
  final Decimal amount;
  final BudgetPeriodType periodType;

  /// Calendar days (time of day is ignored). A monthly budget recurs every
  /// calendar month from the month of [startDate]; [endDate] is required for
  /// custom budgets and inclusive.
  final DateTime startDate;
  final DateTime? endDate;
  final bool alert75;
  final bool alert90;
  final bool alert100;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool alertEnabled(int threshold) => switch (threshold) {
    75 => alert75,
    90 => alert90,
    100 => alert100,
    _ => false,
  };
}
