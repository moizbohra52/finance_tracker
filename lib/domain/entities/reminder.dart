import 'package:decimal/decimal.dart';

/// What a reminder is about. Stored as `reminders.reminder_type`.
enum ReminderType {
  payment('Payment'),
  receivable('Receivable'),
  payable('Payable'),
  khata('Khata'),
  recurring('Recurring'),
  custom('Custom');

  const ReminderType(this.label);

  final String label;

  /// Types that are about a person in the khata.
  bool get involvesContact =>
      this == receivable || this == payable || this == khata;

  /// Types where an amount makes sense.
  bool get hasAmount => this != custom;

  static ReminderType fromName(String? name) => ReminderType.values.firstWhere(
    (ReminderType t) => t.name == name,
    orElse: () => ReminderType.custom,
  );
}

/// How a reminder repeats. [none] is stored as a null `repeat_rule`.
enum ReminderRepeat {
  none('Does not repeat'),
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly'),
  yearly('Yearly');

  const ReminderRepeat(this.label);

  final String label;

  bool get repeats => this != none;

  static ReminderRepeat fromRule(String? rule) => ReminderRepeat.values
      .firstWhere((ReminderRepeat r) => r.name == rule, orElse: () => none);
}

/// Where a reminder is in its life, derived from the data and the clock.
enum ReminderStatus {
  upcoming('Upcoming'),
  snoozed('Snoozed'),
  overdue('Overdue'),
  completed('Completed');

  const ReminderStatus(this.label);

  final String label;
}

/// A dated nudge, optionally about a contact or a transaction. [remindAt] is
/// the schedule (for a repeating reminder, the next occurrence that has not
/// been marked done); [snoozedUntil] temporarily overrides it.
class Reminder {
  const Reminder({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.description,
    required this.amount,
    required this.contactId,
    required this.transactionId,
    required this.remindAt,
    required this.repeat,
    required this.isCompleted,
    required this.notificationEnabled,
    required this.snoozedUntil,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final ReminderType type;
  final String title;
  final String? description;
  final Decimal? amount;
  final String? contactId;
  final String? transactionId;

  /// Local date and time.
  final DateTime remindAt;
  final ReminderRepeat repeat;
  final bool isCompleted;

  /// Whether this reminder should raise a device notification.
  final bool notificationEnabled;
  final DateTime? snoozedUntil;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Reminder copyWith({
    ReminderType? type,
    String? title,
    String? description,
    bool clearDescription = false,
    Decimal? amount,
    bool clearAmount = false,
    String? contactId,
    bool clearContact = false,
    String? transactionId,
    bool clearTransaction = false,
    DateTime? remindAt,
    ReminderRepeat? repeat,
    bool? isCompleted,
    bool? notificationEnabled,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  }) => Reminder(
    id: id,
    userId: userId,
    type: type ?? this.type,
    title: title ?? this.title,
    description: clearDescription ? null : (description ?? this.description),
    amount: clearAmount ? null : (amount ?? this.amount),
    contactId: clearContact ? null : (contactId ?? this.contactId),
    transactionId: clearTransaction
        ? null
        : (transactionId ?? this.transactionId),
    remindAt: remindAt ?? this.remindAt,
    repeat: repeat ?? this.repeat,
    isCompleted: isCompleted ?? this.isCompleted,
    notificationEnabled: notificationEnabled ?? this.notificationEnabled,
    snoozedUntil: clearSnooze ? null : (snoozedUntil ?? this.snoozedUntil),
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    deletedAt: deletedAt,
  );
}
