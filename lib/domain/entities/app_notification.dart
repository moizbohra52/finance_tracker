/// `notifications.type` values the app writes. The column is free text; these
/// are the ones with a meaning in the app.
abstract final class NotificationType {
  static const String reminder = 'reminder';
  static const String budgetAlert = 'budget_alert';
  static const String recurring = 'recurring';
}

/// One notification-center entry (a row of `public.notifications`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.referenceId,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String? body;

  /// The reminder, budget, contact or transaction this is about.
  final String? referenceId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    referenceId: referenceId,
    readAt: readAt ?? at,
    createdAt: createdAt,
  );
}

/// Which device notifications the user wants. Device-local: sound, vibration
/// and permission are all per device, so these are not synced.
class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = true,
    this.reminders = true,
    this.budgets = true,
    this.recurring = true,
    this.sound = true,
    this.vibration = true,
  });

  /// Master switch; when off nothing is scheduled or shown.
  final bool enabled;
  final bool reminders;
  final bool budgets;
  final bool recurring;
  final bool sound;
  final bool vibration;

  /// Whether a notification of [type] may be raised at all.
  bool allows(String type) =>
      enabled &&
      switch (type) {
        NotificationType.reminder => reminders,
        NotificationType.budgetAlert => budgets,
        NotificationType.recurring => recurring,
        _ => true,
      };

  NotificationPreferences copyWith({
    bool? enabled,
    bool? reminders,
    bool? budgets,
    bool? recurring,
    bool? sound,
    bool? vibration,
  }) => NotificationPreferences(
    enabled: enabled ?? this.enabled,
    reminders: reminders ?? this.reminders,
    budgets: budgets ?? this.budgets,
    recurring: recurring ?? this.recurring,
    sound: sound ?? this.sound,
    vibration: vibration ?? this.vibration,
  );
}
