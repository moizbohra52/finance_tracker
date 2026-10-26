import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';

/// Row mapping for public.savings_goals.
abstract final class SavingsGoalModel {
  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// `date` columns arrive as `YYYY-MM-DD`; parse as a local calendar day.
  static DateTime _parseDate(String v) {
    final DateTime d = DateTime.parse(v);
    return DateTime(d.year, d.month, d.day);
  }

  static SavingsGoal fromJson(Map<String, dynamic> json) => SavingsGoal(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    name: json['name'] as String,
    targetAmount: Decimal.parse(json['target_amount'].toString()),
    savedAmount: Decimal.parse(json['saved_amount'].toString()),
    // Joined in by the repository; missing or null means no contributions.
    contributedAmount: Decimal.parse(
      (json['contributed_amount'] ?? '0').toString(),
    ),
    targetDate: json['target_date'] == null
        ? null
        : _parseDate(json['target_date'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
  );

  static Map<String, dynamic> toJson(SavingsGoal g) => <String, dynamic>{
    'id': g.id,
    'user_id': g.userId,
    'name': g.name,
    'target_amount': g.targetAmount.toString(),
    'saved_amount': g.savedAmount.toString(),
    'target_date': g.targetDate == null ? null : _date(g.targetDate!),
  };
}
