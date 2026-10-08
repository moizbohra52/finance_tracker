import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/reminder_fixtures.dart';

void main() {
  final DateTime now = DateTime(2026, 10, 8, 12);

  group('repeat calculation', () {
    test('daily keeps the time of day', () {
      final DateTime anchor = DateTime(2026, 10, 1, 8, 30);
      expect(
        ReminderCalculator.occurrence(anchor, ReminderRepeat.daily, 3),
        DateTime(2026, 10, 4, 8, 30),
      );
    });

    test('weekly steps seven days', () {
      final DateTime anchor = DateTime(2026, 10, 1, 18);
      expect(
        ReminderCalculator.occurrence(anchor, ReminderRepeat.weekly, 2),
        DateTime(2026, 10, 15, 18),
      );
    });

    test('monthly on the 31st stays on month end instead of drifting', () {
      final DateTime anchor = DateTime(2027, 1, 31, 9);
      expect(
        ReminderCalculator.occurrence(anchor, ReminderRepeat.monthly, 1),
        DateTime(2027, 2, 28, 9),
      );
      // Computed from the anchor, not from February, so March is the 31st.
      expect(
        ReminderCalculator.occurrence(anchor, ReminderRepeat.monthly, 2),
        DateTime(2027, 3, 31, 9),
      );
      expect(
        ReminderCalculator.occurrence(anchor, ReminderRepeat.monthly, 3),
        DateTime(2027, 4, 30, 9),
      );
    });

    test('monthly crosses the year', () {
      final DateTime anchor = DateTime(2026, 11, 15, 7);
      expect(
        ReminderCalculator.occurrence(anchor, ReminderRepeat.monthly, 3),
        DateTime(2027, 2, 15, 7),
      );
    });

    test('yearly on 29 February is 28 February in common years', () {
      final DateTime anchor = DateTime(2028, 2, 29, 10);
      expect(
        ReminderCalculator.occurrence(anchor, ReminderRepeat.yearly, 1),
        DateTime(2029, 2, 28, 10),
      );
      expect(
        ReminderCalculator.occurrence(anchor, ReminderRepeat.yearly, 4),
        DateTime(2032, 2, 29, 10),
      );
    });

    test('nextOccurrence returns the anchor while it is still ahead', () {
      final DateTime anchor = DateTime(2026, 12, 1, 9);
      expect(
        ReminderCalculator.nextOccurrence(anchor, ReminderRepeat.monthly, now),
        anchor,
      );
    });

    test('nextOccurrence is strictly after the given moment', () {
      final DateTime anchor = DateTime(2026, 10, 1, 9);
      // Exactly on an occurrence: the next one is returned, not the same.
      expect(
        ReminderCalculator.nextOccurrence(
          anchor,
          ReminderRepeat.weekly,
          DateTime(2026, 10, 8, 9),
        ),
        DateTime(2026, 10, 15, 9),
      );
      expect(
        ReminderCalculator.nextOccurrence(
          anchor,
          ReminderRepeat.daily,
          DateTime(2026, 10, 8, 9, 1),
        ),
        DateTime(2026, 10, 9, 9),
      );
    });

    test('nextOccurrence is null for a one-time reminder in the past', () {
      expect(
        ReminderCalculator.nextOccurrence(
          DateTime(2026, 10, 1, 9),
          ReminderRepeat.none,
          now,
        ),
        isNull,
      );
    });

    test('nextOccurrence handles an anchor years in the past quickly', () {
      final DateTime anchor = DateTime(2020, 1, 31, 9);
      expect(
        ReminderCalculator.nextOccurrence(anchor, ReminderRepeat.monthly, now),
        DateTime(2026, 10, 31, 9),
      );
      expect(
        ReminderCalculator.nextOccurrence(anchor, ReminderRepeat.daily, now),
        DateTime(2026, 10, 9, 9),
      );
      expect(
        ReminderCalculator.nextOccurrence(anchor, ReminderRepeat.yearly, now),
        DateTime(2027, 1, 31, 9),
      );
    });
  });

  group('when a notification fires', () {
    test('a future one-time reminder fires at its time', () {
      final DateTime at = DateTime(2026, 10, 9, 9);
      expect(ReminderCalculator.nextFire(makeReminder(remindAt: at), now), at);
    });

    test('an overdue one-time reminder does not fire', () {
      expect(
        ReminderCalculator.nextFire(
          makeReminder(remindAt: DateTime(2026, 10, 1, 9)),
          now,
        ),
        isNull,
      );
    });

    test('an overdue repeating reminder fires at its next occurrence', () {
      expect(
        ReminderCalculator.nextFire(
          makeReminder(
            remindAt: DateTime(2026, 9, 5, 9),
            repeat: ReminderRepeat.monthly,
          ),
          now,
        ),
        DateTime(2026, 11, 5, 9),
      );
    });

    test('a live snooze replaces the schedule', () {
      final DateTime until = DateTime(2026, 10, 8, 13);
      expect(
        ReminderCalculator.nextFire(
          makeReminder(remindAt: DateTime(2026, 10, 8, 9), snoozedUntil: until),
          now,
        ),
        until,
      );
    });

    test('an expired snooze is ignored', () {
      final DateTime at = DateTime(2026, 10, 9, 9);
      expect(
        ReminderCalculator.nextFire(
          makeReminder(remindAt: at, snoozedUntil: DateTime(2026, 10, 8, 11)),
          now,
        ),
        at,
      );
    });

    test('completed, disabled and deleted reminders never fire', () {
      final DateTime at = DateTime(2026, 10, 9, 9);
      expect(
        ReminderCalculator.nextFire(
          makeReminder(remindAt: at, isCompleted: true),
          now,
        ),
        isNull,
      );
      expect(
        ReminderCalculator.nextFire(
          makeReminder(remindAt: at, notificationEnabled: false),
          now,
        ),
        isNull,
      );
      expect(
        ReminderCalculator.nextFire(
          makeReminder(remindAt: at, deletedAt: now),
          now,
        ),
        isNull,
      );
    });
  });

  group('awaiting delivery (late OS alarms)', () {
    // now = 12:00. Android may deliver an inexact alarm minutes late, so a
    // notification that came due a moment ago can still be on its way.
    test('a one-time reminder that just came due is awaiting delivery', () {
      final Reminder r = makeReminder(remindAt: DateTime(2026, 10, 8, 11, 55));
      expect(ReminderCalculator.isAwaitingDelivery(r, now), isTrue);
    });

    test('...but not once the grace period has passed', () {
      final Reminder r = makeReminder(remindAt: DateTime(2026, 10, 8, 11, 40));
      expect(ReminderCalculator.isAwaitingDelivery(r, now), isFalse);
    });

    test('a future reminder is not awaiting delivery', () {
      final Reminder r = makeReminder(remindAt: DateTime(2026, 10, 8, 12, 1));
      expect(ReminderCalculator.isAwaitingDelivery(r, now), isFalse);
    });

    test(
      "today's occurrence of an old daily reminder is awaiting delivery",
      () {
        // Anchored last week; today's 11:58 occurrence just passed.
        final Reminder r = makeReminder(
          remindAt: DateTime(2026, 10, 1, 11, 58),
          repeat: ReminderRepeat.daily,
        );
        expect(ReminderCalculator.isAwaitingDelivery(r, now), isTrue);
        // An hour later it has been and gone; tomorrow's is next.
        expect(
          ReminderCalculator.isAwaitingDelivery(r, DateTime(2026, 10, 8, 13)),
          isFalse,
        );
      },
    );

    test('a monthly reminder is only in flight on its day', () {
      final Reminder r = makeReminder(
        remindAt: DateTime(2026, 8, 8, 11, 58),
        repeat: ReminderRepeat.monthly,
      );
      expect(ReminderCalculator.isAwaitingDelivery(r, now), isTrue);
      expect(
        ReminderCalculator.isAwaitingDelivery(r, DateTime(2026, 10, 9, 12)),
        isFalse,
      );
    });

    test(
      'a live snooze is scheduled normally, an expired one is in flight',
      () {
        expect(
          ReminderCalculator.isAwaitingDelivery(
            makeReminder(
              remindAt: DateTime(2026, 10, 8, 11, 58),
              snoozedUntil: DateTime(2026, 10, 8, 13),
            ),
            now,
          ),
          isFalse,
        );
        expect(
          ReminderCalculator.isAwaitingDelivery(
            makeReminder(
              remindAt: DateTime(2026, 10, 1, 9),
              snoozedUntil: DateTime(2026, 10, 8, 11, 55),
            ),
            now,
          ),
          isTrue,
        );
      },
    );

    test('completed, disabled and deleted reminders never are', () {
      final DateTime due = DateTime(2026, 10, 8, 11, 55);
      expect(
        ReminderCalculator.isAwaitingDelivery(
          makeReminder(remindAt: due, isCompleted: true),
          now,
        ),
        isFalse,
      );
      expect(
        ReminderCalculator.isAwaitingDelivery(
          makeReminder(remindAt: due, notificationEnabled: false),
          now,
        ),
        isFalse,
      );
      expect(
        ReminderCalculator.isAwaitingDelivery(
          makeReminder(remindAt: due, deletedAt: now),
          now,
        ),
        isFalse,
      );
    });
  });

  group('status', () {
    test('upcoming, overdue, snoozed and completed', () {
      expect(
        ReminderCalculator.status(
          makeReminder(remindAt: DateTime(2026, 10, 9)),
          now,
        ),
        ReminderStatus.upcoming,
      );
      expect(
        ReminderCalculator.status(
          makeReminder(remindAt: DateTime(2026, 10, 7)),
          now,
        ),
        ReminderStatus.overdue,
      );
      expect(
        ReminderCalculator.status(
          makeReminder(
            remindAt: DateTime(2026, 10, 7),
            snoozedUntil: DateTime(2026, 10, 8, 14),
          ),
          now,
        ),
        ReminderStatus.snoozed,
      );
      expect(
        ReminderCalculator.status(
          makeReminder(remindAt: DateTime(2026, 10, 7), isCompleted: true),
          now,
        ),
        ReminderStatus.completed,
      );
    });
  });

  group('complete', () {
    test('a one-time reminder is completed and its snooze cleared', () {
      final Reminder done = ReminderCalculator.complete(
        makeReminder(
          remindAt: DateTime(2026, 10, 7),
          snoozedUntil: DateTime(2026, 10, 8, 14),
        ),
        now,
      );
      expect(done.isCompleted, isTrue);
      expect(done.snoozedUntil, isNull);
    });

    test('a repeating reminder moves to the next occurrence', () {
      final Reminder next = ReminderCalculator.complete(
        makeReminder(
          remindAt: DateTime(2026, 10, 5, 9),
          repeat: ReminderRepeat.monthly,
        ),
        now,
      );
      expect(next.isCompleted, isFalse);
      expect(next.remindAt, DateTime(2026, 11, 5, 9));
    });

    test('completing a repeating reminder early skips this occurrence', () {
      final Reminder next = ReminderCalculator.complete(
        makeReminder(
          remindAt: DateTime(2026, 10, 20, 9),
          repeat: ReminderRepeat.monthly,
        ),
        now,
      );
      expect(next.remindAt, DateTime(2026, 11, 20, 9));
    });

    test('reopen brings a completed reminder back', () {
      final Reminder open = ReminderCalculator.reopen(
        makeReminder(remindAt: DateTime(2026, 10, 7), isCompleted: true),
      );
      expect(open.isCompleted, isFalse);
    });
  });

  group('snooze', () {
    test('presets', () {
      expect(
        ReminderCalculator.snoozeUntil(SnoozeOption.fifteenMinutes, now),
        DateTime(2026, 10, 8, 12, 15),
      );
      expect(
        ReminderCalculator.snoozeUntil(SnoozeOption.oneHour, now),
        DateTime(2026, 10, 8, 13),
      );
      expect(
        ReminderCalculator.snoozeUntil(SnoozeOption.threeHours, now),
        DateTime(2026, 10, 8, 15),
      );
      expect(
        ReminderCalculator.snoozeUntil(SnoozeOption.tomorrowMorning, now),
        DateTime(2026, 10, 9, 9),
      );
    });

    test('tomorrow morning crosses a month end', () {
      expect(
        ReminderCalculator.snoozeUntil(
          SnoozeOption.tomorrowMorning,
          DateTime(2026, 10, 31, 22),
        ),
        DateTime(2026, 11, 1, 9),
      );
    });
  });
}
