import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:uuid/uuid.dart';

/// Stable ids for notifications. The OS keys a scheduled notification by an
/// int, so deriving it from the reminder id means scheduling the same reminder
/// again replaces the old entry instead of stacking a duplicate. Event ids
/// (for the notification center) are UUIDs because the table wants one.
abstract final class NotificationIds {
  static const int _max = 0x7fffffff;

  /// FNV-1a over [key], folded to a positive 31-bit int (Android and iOS both
  /// take a 32-bit signed id). Deterministic across runs and devices.
  static int _hash(String key) {
    int hash = 0x811c9dc5;
    for (final int unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash & _max;
  }

  static int forReminder(String reminderId) => _hash('reminder:$reminderId');

  /// Device id for an immediate notification about the stored event [eventId].
  static int forEvent(String eventId) => _hash('event:$eventId');

  /// Id of the notification-center entry for "this reminder became due". It
  /// depends on the reminder and the due time, so every device derives the
  /// same id and the entry is created once; completing a repeating reminder
  /// moves its due time and so starts a new entry.
  static String dueEventId(Reminder reminder) => const Uuid().v5(
    Namespace.url.value,
    'reminder-due:${reminder.id}:${reminder.remindAt.millisecondsSinceEpoch}',
  );
}

/// One notification the device should hold, fully decided: what the OS needs
/// and nothing else.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.fireAt,
    required this.repeat,
  });

  final int id;
  final String title;
  final String body;

  /// `reminder:<id>`; see NotificationTarget for how taps use it.
  final String payload;

  /// Local time of the next fire.
  final DateTime fireAt;

  /// OS-level repeat after [fireAt]; [ReminderRepeat.none] for one-shots.
  final ReminderRepeat repeat;
}

/// Turns reminders into the exact set of notifications the device should have
/// scheduled. The caller replaces whatever is scheduled with this set, which
/// is what makes scheduling idempotent: ids are stable, so rerunning with the
/// same input changes nothing, and anything not in the set is cancelled.
abstract final class ReminderNotificationPlanner {
  /// iOS keeps at most 64 pending local notifications; leave room for others.
  static const int maxScheduled = 60;

  static String payloadFor(String reminderId) =>
      '${NotificationType.reminder}:$reminderId';

  /// Notification text carries only what the user typed as the title plus a
  /// generic line. Amounts and contact names are never put in a notification:
  /// it can be read on a locked screen.
  static String bodyFor(ReminderType type) => switch (type) {
    ReminderType.payment => 'Payment reminder',
    ReminderType.receivable => 'Money to collect',
    ReminderType.payable => 'Money to pay',
    ReminderType.khata => 'Khata reminder',
    ReminderType.recurring => 'Recurring transaction reminder',
    ReminderType.custom => 'Reminder',
  };

  /// Ids of notifications that are due but may not have been delivered yet.
  /// They are neither rescheduled nor cancelled; see
  /// [ReminderCalculator.deliveryGrace].
  static Set<int> inFlightIds(
    List<Reminder> reminders,
    DateTime now,
    NotificationPreferences preferences,
  ) {
    if (!preferences.allows(NotificationType.reminder)) return <int>{};
    return <int>{
      for (final Reminder r in reminders)
        if (ReminderCalculator.isAwaitingDelivery(r, now))
          NotificationIds.forReminder(r.id),
    };
  }

  static List<PlannedNotification> plan(
    List<Reminder> reminders,
    DateTime now,
    NotificationPreferences preferences,
  ) {
    if (!preferences.allows(NotificationType.reminder)) {
      return const <PlannedNotification>[];
    }
    final List<PlannedNotification> out = <PlannedNotification>[];
    final Set<int> used = <int>{};
    // Sorted so that, on the astronomically rare id collision, the same
    // reminder always keeps the id on every run.
    final List<Reminder> sorted = List<Reminder>.of(reminders)
      ..sort((Reminder a, Reminder b) => a.id.compareTo(b.id));
    for (final Reminder r in sorted) {
      if (ReminderCalculator.isAwaitingDelivery(r, now)) continue;
      final DateTime? fireAt = ReminderCalculator.nextFire(r, now);
      if (fireAt == null) continue;
      int id = NotificationIds.forReminder(r.id);
      while (!used.add(id)) {
        id = (id + 1) & 0x7fffffff;
      }
      final bool snoozed =
          r.snoozedUntil != null && r.snoozedUntil!.isAfter(now);
      out.add(
        PlannedNotification(
          id: id,
          title: r.title,
          body: bodyFor(r.type),
          payload: payloadFor(r.id),
          fireAt: fireAt,
          // A snooze is a single extra nudge; the series resumes afterwards.
          repeat: snoozed ? ReminderRepeat.none : r.repeat,
        ),
      );
    }
    out.sort(
      (PlannedNotification a, PlannedNotification b) =>
          a.fireAt.compareTo(b.fireAt),
    );
    return out.length <= maxScheduled ? out : out.sublist(0, maxScheduled);
  }
}
