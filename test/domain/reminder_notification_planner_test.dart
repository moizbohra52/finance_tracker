import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_notification_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/reminder_fixtures.dart';

void main() {
  final DateTime now = DateTime(2026, 10, 8, 12);
  const NotificationPreferences on = NotificationPreferences();

  String idOf(int n) =>
      'a1b2c3d4-0000-4000-8000-${n.toString().padLeft(12, '0')}';

  group('notification id generation', () {
    test('is stable for the same reminder', () {
      expect(
        NotificationIds.forReminder(idOf(1)),
        NotificationIds.forReminder(idOf(1)),
      );
    });

    test('is pinned, so it never changes between app versions', () {
      // A change here would orphan every scheduled notification on devices
      // that update the app.
      expect(NotificationIds.forReminder(idOf(1)), 1629550436);
    });

    test('differs between reminders', () {
      final Set<int> ids = <int>{
        for (int i = 0; i < 2000; i++) NotificationIds.forReminder(idOf(i)),
      };
      expect(ids.length, 2000);
    });

    test('fits a 32-bit signed int and is never negative', () {
      for (int i = 0; i < 2000; i++) {
        final int id = NotificationIds.forReminder(idOf(i));
        expect(id, inInclusiveRange(0, 0x7fffffff));
      }
    });

    test('reminder and event ids live in different spaces', () {
      expect(
        NotificationIds.forReminder(idOf(1)),
        isNot(NotificationIds.forEvent(idOf(1))),
      );
    });

    test('the due event id changes with the due time, not with a reload', () {
      final Reminder r = makeReminder(remindAt: DateTime(2026, 10, 7, 9));
      expect(NotificationIds.dueEventId(r), NotificationIds.dueEventId(r));
      expect(
        NotificationIds.dueEventId(r),
        isNot(
          NotificationIds.dueEventId(
            r.copyWith(remindAt: DateTime(2026, 11, 7, 9)),
          ),
        ),
      );
    });
  });

  group('planning', () {
    test('plans each live reminder once, with its stable id', () {
      final List<Reminder> reminders = <Reminder>[
        makeReminder(id: idOf(1), remindAt: DateTime(2026, 10, 9, 9)),
        makeReminder(id: idOf(2), remindAt: DateTime(2026, 10, 10, 9)),
      ];
      final List<PlannedNotification> plan = ReminderNotificationPlanner.plan(
        reminders,
        now,
        on,
      );
      expect(plan.map((PlannedNotification n) => n.id).toList(), <int>[
        NotificationIds.forReminder(idOf(1)),
        NotificationIds.forReminder(idOf(2)),
      ]);
    });

    test('planning twice gives the same result (no duplicates)', () {
      final List<Reminder> reminders = <Reminder>[
        makeReminder(id: idOf(1), remindAt: DateTime(2026, 10, 9, 9)),
        makeReminder(id: idOf(2), remindAt: DateTime(2026, 10, 10, 9)),
      ];
      List<(int, DateTime)> run() => ReminderNotificationPlanner.plan(
        reminders,
        now,
        on,
      ).map((PlannedNotification n) => (n.id, n.fireAt)).toList();
      expect(run(), run());
      expect(run().map(((int, DateTime) e) => e.$1).toSet().length, 2);
    });

    test('the same reminder listed twice is scheduled under distinct ids', () {
      // A duplicate row can never share a notification; the second one is
      // moved to the next free id rather than overwriting the first.
      final Reminder r = makeReminder(
        id: idOf(1),
        remindAt: DateTime(2026, 10, 9, 9),
      );
      final List<PlannedNotification> plan = ReminderNotificationPlanner.plan(
        <Reminder>[r, r],
        now,
        on,
      );
      expect(plan.map((PlannedNotification n) => n.id).toSet().length, 2);
    });

    test('skips completed, disabled, deleted and overdue one-time ones', () {
      final List<Reminder> reminders = <Reminder>[
        makeReminder(
          id: idOf(1),
          remindAt: DateTime(2026, 10, 9),
          isCompleted: true,
        ),
        makeReminder(
          id: idOf(2),
          remindAt: DateTime(2026, 10, 9),
          notificationEnabled: false,
        ),
        makeReminder(
          id: idOf(3),
          remindAt: DateTime(2026, 10, 9),
          deletedAt: now,
        ),
        makeReminder(id: idOf(4), remindAt: DateTime(2026, 10, 1)),
        makeReminder(id: idOf(5), remindAt: DateTime(2026, 10, 9)),
      ];
      final List<PlannedNotification> plan = ReminderNotificationPlanner.plan(
        reminders,
        now,
        on,
      );
      expect(plan, hasLength(1));
      expect(plan.single.payload, 'reminder:${idOf(5)}');
    });

    test('a repeating reminder keeps its repeat at its next occurrence', () {
      final PlannedNotification n = ReminderNotificationPlanner.plan(
        <Reminder>[
          makeReminder(
            remindAt: DateTime(2026, 9, 5, 9),
            repeat: ReminderRepeat.monthly,
          ),
        ],
        now,
        on,
      ).single;
      expect(n.fireAt, DateTime(2026, 11, 5, 9));
      expect(n.repeat, ReminderRepeat.monthly);
    });

    test('a snooze is a one-shot, even for a repeating reminder', () {
      final PlannedNotification n = ReminderNotificationPlanner.plan(
        <Reminder>[
          makeReminder(
            remindAt: DateTime(2026, 10, 8, 9),
            repeat: ReminderRepeat.daily,
            snoozedUntil: DateTime(2026, 10, 8, 13),
          ),
        ],
        now,
        on,
      ).single;
      expect(n.fireAt, DateTime(2026, 10, 8, 13));
      expect(n.repeat, ReminderRepeat.none);
    });

    test('a notification still on its way is left alone, not replaced', () {
      // Daily reminder whose 11:58 occurrence is 2 minutes old: planning
      // tomorrow's under the same id would cancel today's pending alarm.
      final Reminder due = makeReminder(
        id: idOf(1),
        remindAt: DateTime(2026, 10, 1, 11, 58),
        repeat: ReminderRepeat.daily,
      );
      final Reminder later = makeReminder(
        id: idOf(2),
        remindAt: DateTime(2026, 10, 9, 9),
      );
      expect(
        ReminderNotificationPlanner.plan(
          <Reminder>[due, later],
          now,
          on,
        ).map((PlannedNotification n) => n.id),
        <int>[NotificationIds.forReminder(idOf(2))],
      );
      expect(
        ReminderNotificationPlanner.inFlightIds(
          <Reminder>[due, later],
          now,
          on,
        ),
        <int>{NotificationIds.forReminder(idOf(1))},
      );
    });

    test('once the grace period is over it rolls to the next occurrence', () {
      final Reminder r = makeReminder(
        remindAt: DateTime(2026, 10, 1, 11, 58),
        repeat: ReminderRepeat.daily,
      );
      final DateTime later = DateTime(2026, 10, 8, 12, 30);
      expect(
        ReminderNotificationPlanner.inFlightIds(<Reminder>[r], later, on),
        isEmpty,
      );
      expect(
        ReminderNotificationPlanner.plan(
          <Reminder>[r],
          later,
          on,
        ).single.fireAt,
        DateTime(2026, 10, 9, 11, 58),
      );
    });

    test('nothing is in flight when notifications are off', () {
      final Reminder r = makeReminder(remindAt: DateTime(2026, 10, 8, 11, 58));
      expect(
        ReminderNotificationPlanner.inFlightIds(
          <Reminder>[r],
          now,
          const NotificationPreferences(enabled: false),
        ),
        isEmpty,
      );
    });

    test('nothing is planned when notifications or reminders are off', () {
      final List<Reminder> reminders = <Reminder>[
        makeReminder(remindAt: DateTime(2026, 10, 9)),
      ];
      expect(
        ReminderNotificationPlanner.plan(
          reminders,
          now,
          const NotificationPreferences(enabled: false),
        ),
        isEmpty,
      );
      expect(
        ReminderNotificationPlanner.plan(
          reminders,
          now,
          const NotificationPreferences(reminders: false),
        ),
        isEmpty,
      );
    });

    test('is ordered by fire time and capped for the iOS limit', () {
      final List<Reminder> reminders = <Reminder>[
        for (int i = 0; i < 100; i++)
          makeReminder(
            id: idOf(i),
            remindAt: DateTime(2026, 10, 9).add(Duration(hours: 100 - i)),
          ),
      ];
      final List<PlannedNotification> plan = ReminderNotificationPlanner.plan(
        reminders,
        now,
        on,
      );
      expect(plan, hasLength(ReminderNotificationPlanner.maxScheduled));
      for (int i = 1; i < plan.length; i++) {
        expect(plan[i].fireAt.isBefore(plan[i - 1].fireAt), isFalse);
      }
      // The soonest ones are kept.
      expect(
        plan.first.fireAt,
        DateTime(2026, 10, 9).add(const Duration(hours: 1)),
      );
    });

    test('notification text never contains the amount or contact', () {
      final PlannedNotification n = ReminderNotificationPlanner.plan(
        <Reminder>[
          makeReminder(
            type: ReminderType.receivable,
            title: 'Collect payment',
            amount: '12500.50',
            contactId: 'c-1',
            remindAt: DateTime(2026, 10, 9, 9),
          ),
        ],
        now,
        on,
      ).single;
      expect(n.title, 'Collect payment');
      expect('${n.title} ${n.body} ${n.payload}', isNot(contains('12500')));
      expect(n.payload, isNot(contains('c-1')));
      expect(n.body, 'Money to collect');
    });
  });
}
