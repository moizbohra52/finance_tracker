import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';

/// Row mapping for public.reminders.
abstract final class ReminderModel {
  static DateTime _parse(Object? value) =>
      DateTime.parse(value as String).toLocal();

  static Reminder fromJson(Map<String, dynamic> json) => Reminder(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    // The three columns below arrive with the Phase 09 migration.
    type: ReminderType.fromName(json['reminder_type'] as String?),
    title: json['title'] as String,
    description: json['description'] as String?,
    amount: json['amount'] == null
        ? null
        : Decimal.parse(json['amount'].toString()),
    contactId: json['contact_id'] as String?,
    transactionId: json['transaction_id'] as String?,
    remindAt: _parse(json['remind_at']),
    repeat: ReminderRepeat.fromRule(json['repeat_rule'] as String?),
    isCompleted: json['is_completed'] == true || json['is_completed'] == 1,
    notificationEnabled: json['notification_enabled'] == null
        ? true
        : (json['notification_enabled'] == true ||
              json['notification_enabled'] == 1),
    snoozedUntil: json['snoozed_until'] == null
        ? null
        : _parse(json['snoozed_until']),
    createdAt: _parse(json['created_at']),
    updatedAt: _parse(json['updated_at']),
    deletedAt: json['deleted_at'] == null ? null : _parse(json['deleted_at']),
  );

  static Map<String, dynamic> toJson(Reminder r) => <String, dynamic>{
    'id': r.id,
    'user_id': r.userId,
    'reminder_type': r.type.name,
    'title': r.title,
    'description': r.description,
    'amount': r.amount?.toString(),
    'contact_id': r.contactId,
    'transaction_id': r.transactionId,
    'remind_at': r.remindAt.toUtc().toIso8601String(),
    'repeat_rule': r.repeat.repeats ? r.repeat.name : null,
    'is_completed': r.isCompleted,
    'notification_enabled': r.notificationEnabled,
    'snoozed_until': r.snoozedUntil?.toUtc().toIso8601String(),
  };
}
