import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';

/// A reminder with sensible defaults; override only what a test is about.
Reminder makeReminder({
  String id = 'a1b2c3d4-0000-4000-8000-000000000001',
  ReminderType type = ReminderType.custom,
  String title = 'Pay rent',
  String? description,
  String? amount,
  String? contactId,
  String? transactionId,
  required DateTime remindAt,
  ReminderRepeat repeat = ReminderRepeat.none,
  bool isCompleted = false,
  bool notificationEnabled = true,
  DateTime? snoozedUntil,
  DateTime? deletedAt,
}) => Reminder(
  id: id,
  userId: 'u',
  type: type,
  title: title,
  description: description,
  amount: amount == null ? null : Decimal.parse(amount),
  contactId: contactId,
  transactionId: transactionId,
  remindAt: remindAt,
  repeat: repeat,
  isCompleted: isCompleted,
  notificationEnabled: notificationEnabled,
  snoozedUntil: snoozedUntil,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  deletedAt: deletedAt,
);
