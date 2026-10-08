import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/recurring_scheduler.dart';

/// How long a snooze lasts.
enum SnoozeOption {
  fifteenMinutes('15 minutes'),
  oneHour('1 hour'),
  threeHours('3 hours'),
  tomorrowMorning('Tomorrow, 9:00 AM');

  const SnoozeOption(this.label);

  final String label;
}

/// Date maths and state rules for reminders. No I/O, no clock: every method
/// takes `now`, so behaviour is deterministic in tests.
abstract final class ReminderCalculator {
  /// Local hour used by [SnoozeOption.tomorrowMorning].
  static const int morningHour = 9;

  /// How long after its time a notification may still be on its way. Android
  /// delivers inexact alarms late (up to about 15 minutes in Doze), so for
  /// this long the pending OS alarm is left alone rather than replaced by the
  /// next occurrence, which would silently drop a notification that is about
  /// to appear.
  static const Duration deliveryGrace = Duration(minutes: 15);

  static RecurringFrequency _frequency(ReminderRepeat repeat) =>
      RecurringFrequency.values.byName(repeat.name);

  /// Occurrence [index] (0 = [anchor]) of a repeating series, keeping the
  /// anchor's time of day. Months are clamped to month end, so a reminder
  /// anchored on the 31st stays on the last day of shorter months instead of
  /// drifting, and 29 February becomes 28 February in common years.
  static DateTime occurrence(
    DateTime anchor,
    ReminderRepeat repeat,
    int index,
  ) {
    // The scheduler already does the calendar maths; only its fixed 09:00 run
    // time is replaced with the reminder's own time of day.
    final DateTime day = RecurringScheduler.occurrence(
      anchor,
      _frequency(repeat),
      1,
      index,
    );
    return DateTime(day.year, day.month, day.day, anchor.hour, anchor.minute);
  }

  /// First occurrence of the series strictly after [after]; null for a
  /// reminder that does not repeat and is not later than [after].
  static DateTime? nextOccurrence(
    DateTime anchor,
    ReminderRepeat repeat,
    DateTime after,
  ) {
    if (anchor.isAfter(after)) return anchor;
    if (!repeat.repeats) return null;
    int index = _estimateIndex(anchor, repeat, after);
    // The estimate can land a step early or late (month lengths); settle it.
    while (index > 0 && occurrence(anchor, repeat, index - 1).isAfter(after)) {
      index--;
    }
    while (!occurrence(anchor, repeat, index).isAfter(after)) {
      index++;
    }
    return occurrence(anchor, repeat, index);
  }

  /// A starting guess for how many whole periods fit between the dates, so
  /// a years-old daily reminder does not loop thousands of times.
  static int _estimateIndex(
    DateTime anchor,
    ReminderRepeat repeat,
    DateTime after,
  ) {
    final int days = after.difference(anchor).inDays;
    final int guess = switch (repeat) {
      ReminderRepeat.none => 0,
      ReminderRepeat.daily => days,
      ReminderRepeat.weekly => days ~/ 7,
      ReminderRepeat.monthly => days ~/ 31,
      ReminderRepeat.yearly => days ~/ 366,
    };
    return guess < 0 ? 0 : guess;
  }

  /// When the next notification should fire, or null when none should.
  ///
  /// A live snooze wins. Otherwise a future [Reminder.remindAt] is used; a
  /// repeating reminder whose time has passed fires at its next occurrence;
  /// a one-time reminder that is already past is overdue and stays silent.
  static DateTime? nextFire(Reminder r, DateTime now) {
    if (r.deletedAt != null || r.isCompleted || !r.notificationEnabled) {
      return null;
    }
    final DateTime? snooze = r.snoozedUntil;
    if (snooze != null && snooze.isAfter(now)) return snooze;
    return nextOccurrence(r.remindAt, r.repeat, now);
  }

  /// A live reminder with a notification that came due within
  /// [deliveryGrace], so it may still be pending delivery and its OS alarm
  /// must not be touched. Looks at every occurrence of a repeating series, not
  /// just the stored anchor, because today's occurrence of a daily reminder
  /// anchored last week is just as much "in flight".
  static bool isAwaitingDelivery(Reminder r, DateTime now) {
    if (r.deletedAt != null || r.isCompleted || !r.notificationEnabled) {
      return false;
    }
    final DateTime windowStart = now.subtract(deliveryGrace);
    final DateTime? snooze = r.snoozedUntil;
    if (snooze != null) {
      // A live snooze is scheduled normally; one that just ran out is in flight.
      if (snooze.isAfter(now)) return false;
      if (snooze.isAfter(windowStart)) return true;
    }
    final DateTime? occurrence = nextOccurrence(
      r.remindAt,
      r.repeat,
      windowStart,
    );
    return occurrence != null && !occurrence.isAfter(now);
  }

  static ReminderStatus status(Reminder r, DateTime now) {
    if (r.isCompleted) return ReminderStatus.completed;
    final DateTime? snooze = r.snoozedUntil;
    if (snooze != null && snooze.isAfter(now)) return ReminderStatus.snoozed;
    return r.remindAt.isAfter(now)
        ? ReminderStatus.upcoming
        : ReminderStatus.overdue;
  }

  /// Marks the current occurrence done. A one-time reminder is completed; a
  /// repeating one moves to its next occurrence and stays active.
  static Reminder complete(Reminder r, DateTime now) {
    if (!r.repeat.repeats) {
      return r.copyWith(isCompleted: true, clearSnooze: true);
    }
    // After the later of "now" and the current due time, so completing early
    // skips this occurrence and completing late does not land in the past.
    final DateTime from = r.remindAt.isAfter(now) ? r.remindAt : now;
    return r.copyWith(
      remindAt: nextOccurrence(r.remindAt, r.repeat, from),
      clearSnooze: true,
    );
  }

  /// Brings a completed one-time reminder back as active.
  static Reminder reopen(Reminder r) => r.copyWith(isCompleted: false);

  static DateTime snoozeUntil(SnoozeOption option, DateTime now) =>
      switch (option) {
        SnoozeOption.fifteenMinutes => now.add(const Duration(minutes: 15)),
        SnoozeOption.oneHour => now.add(const Duration(hours: 1)),
        SnoozeOption.threeHours => now.add(const Duration(hours: 3)),
        SnoozeOption.tomorrowMorning => DateTime(
          now.year,
          now.month,
          now.day + 1,
          morningHour,
        ),
      };
}
