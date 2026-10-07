import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/budget.dart';

/// Row mapping for public.budgets.
abstract final class BudgetModel {
  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// `date` columns arrive as `YYYY-MM-DD`; parse as a local calendar day.
  static DateTime _parseDate(String v) {
    final DateTime d = DateTime.parse(v);
    return DateTime(d.year, d.month, d.day);
  }

  static Budget fromJson(Map<String, dynamic> json) => Budget(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    categoryId: json['category_id'] as String?,
    amount: Decimal.parse(json['amount'].toString()),
    periodType: json['period_type'] == 'custom'
        ? BudgetPeriodType.custom
        : BudgetPeriodType.monthly,
    startDate: _parseDate(json['start_date'] as String),
    endDate: json['end_date'] == null
        ? null
        : _parseDate(json['end_date'] as String),
    alert75: json['alert_75'] as bool? ?? true,
    alert90: json['alert_90'] as bool? ?? true,
    alert100: json['alert_100'] as bool? ?? true,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
  );

  static Map<String, dynamic> toJson(Budget b) => <String, dynamic>{
    'id': b.id,
    'user_id': b.userId,
    'category_id': b.categoryId,
    'amount': b.amount.toString(),
    'period_type': b.periodType.name,
    'start_date': _date(b.startDate),
    // A monthly budget has no end; the table allows null only then.
    'end_date': b.periodType == BudgetPeriodType.custom && b.endDate != null
        ? _date(b.endDate!)
        : null,
    'alert_75': b.alert75,
    'alert_90': b.alert90,
    'alert_100': b.alert100,
  };
}
