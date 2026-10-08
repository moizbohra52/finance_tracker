import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';

/// Row mapping for public.recurring_transactions.
abstract final class RecurringTransactionModel {
  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime _parseDate(String v) {
    final DateTime d = DateTime.parse(v);
    return DateTime(d.year, d.month, d.day);
  }

  static RecurringTransaction fromJson(Map<String, dynamic> json) =>
      RecurringTransaction(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        accountId: json['account_id'] as String,
        categoryId: json['category_id'] as String?,
        type: json['type'] == 'income'
            ? TransactionType.income
            : TransactionType.expense,
        amount: Decimal.parse(json['amount'].toString()),
        frequency: RecurringFrequency.values.firstWhere(
          (RecurringFrequency f) => f.name == json['frequency'],
          orElse: () => RecurringFrequency.monthly,
        ),
        // Absent until the interval_count migration is applied.
        intervalCount: (json['interval_count'] as num?)?.toInt() ?? 1,
        startDate: _parseDate(json['start_date'] as String),
        endDate: json['end_date'] == null
            ? null
            : _parseDate(json['end_date'] as String),
        nextRunAt: DateTime.parse(json['next_run_at'] as String).toLocal(),
        active: json['active'] == null
            ? true
            : (json['active'] == true || json['active'] == 1),
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String),
      );

  static Map<String, dynamic> toJson(RecurringTransaction r) =>
      <String, dynamic>{
        'id': r.id,
        'user_id': r.userId,
        'account_id': r.accountId,
        'category_id': r.categoryId,
        'type': r.type == TransactionType.income ? 'income' : 'expense',
        'amount': r.amount.toString(),
        'frequency': r.frequency.name,
        // Only sent when it differs from the default, so standard schedules
        // keep working on a database without the interval_count column.
        if (r.intervalCount != 1) 'interval_count': r.intervalCount,
        'start_date': _date(r.startDate),
        'end_date': r.endDate == null ? null : _date(r.endDate!),
        'next_run_at': r.nextRunAt.toUtc().toIso8601String(),
        'active': r.active,
        'note': r.note,
      };
}
