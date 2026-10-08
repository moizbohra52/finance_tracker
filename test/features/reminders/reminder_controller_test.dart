import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/notification_permission_state.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:finance_tracker/domain/services/reminder_notification_planner.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fake_notifications.dart';
import '../../helpers/fakes.dart';
import '../../helpers/reminder_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFinance finance;
  late NotificationsHandle notifications;
  late ReminderController controller;

  Future<void> setUpController({bool granted = true}) async {
    finance = FakeFinance();
    notifications = await buildCoordinator(
      finance,
      auth: FakeAuthRepository(signedIn: true),
      local: FakeLocalNotifications(granted: granted),
    );
    await notifications.coordinator.initialize();
    controller = ReminderController(
      finance.repositories.reminders,
      finance.repositories.contacts,
      notifications.coordinator,
      DataChangeNotifier(),
    );
    await controller.load();
  }

  setUp(setUpController);

  DateTime soon([int days = 2]) =>
      DateTime.now().add(Duration(days: days, minutes: 7));

  Future<bool> create({
    String id = 'a1b2c3d4-0000-4000-8000-000000000001',
    String title = 'Pay rent',
    ReminderType type = ReminderType.payment,
    ReminderRepeat repeat = ReminderRepeat.none,
    bool notify = true,
    DateTime? at,
    String? contactId,
    Decimal? amount,
  }) => controller.saveReminder(
    id: id,
    type: type,
    title: title,
    description: null,
    amount: amount,
    contactId: contactId,
    transactionId: null,
    remindAt: at ?? soon(),
    repeat: repeat,
    notificationEnabled: notify,
  );

  group('creation', () {
    test('saves the reminder and schedules one notification', () async {
      expect(await create(), isTrue);

      expect(finance.reminders, hasLength(1));
      expect(controller.reminders, hasLength(1));
      final Reminder saved = finance.reminders.single;
      expect(saved.title, 'Pay rent');
      expect(saved.isCompleted, isFalse);
      expect(notifications.local.scheduled.keys, <int>[
        NotificationIds.forReminder(saved.id),
      ]);
    });

    test('keeps type, amount, contact, repeat and the notify flag', () async {
      await create(
        type: ReminderType.receivable,
        amount: Decimal.parse('1250.50'),
        contactId: 'c-1',
        repeat: ReminderRepeat.monthly,
        notify: false,
      );
      final Reminder saved = finance.reminders.single;
      expect(saved.type, ReminderType.receivable);
      expect(saved.amount, Decimal.parse('1250.50'));
      expect(saved.contactId, 'c-1');
      expect(saved.repeat, ReminderRepeat.monthly);
      expect(saved.notificationEnabled, isFalse);
      expect(notifications.local.scheduled, isEmpty, reason: 'notify is off');
    });

    test('a custom reminder drops amount and contact', () async {
      await create(
        type: ReminderType.custom,
        amount: Decimal.parse('5'),
        contactId: 'c-1',
      );
      expect(finance.reminders.single.amount, isNull);
      expect(finance.reminders.single.contactId, isNull);
    });

    test('a retried save with the same id never duplicates', () async {
      await create();
      await create();
      expect(finance.reminders, hasLength(1));
      expect(notifications.local.scheduled, hasLength(1));
    });

    test('a failed save reports the error and stores nothing', () async {
      finance.nextError = const NetworkFailure();
      expect(await create(), isFalse);
      expect(controller.save.error.value, isNotNull);
      expect(finance.reminders, isEmpty);
      expect(notifications.local.scheduled, isEmpty);
    });
  });

  group('update', () {
    test('changes the stored reminder and moves its notification', () async {
      await create();
      final Reminder saved = finance.reminders.single;
      final DateTime later = soon(5);

      expect(
        await controller.saveReminder(
          id: saved.id,
          existing: saved,
          type: ReminderType.payment,
          title: 'Pay rent (October)',
          description: 'Transfer from the bank',
          amount: Decimal.parse('12000'),
          contactId: null,
          transactionId: null,
          remindAt: later,
          repeat: ReminderRepeat.none,
          notificationEnabled: true,
        ),
        isTrue,
      );

      final Reminder edited = finance.reminders.single;
      expect(edited.title, 'Pay rent (October)');
      expect(edited.description, 'Transfer from the bank');
      expect(edited.amount, Decimal.parse('12000'));
      expect(finance.reminders, hasLength(1));
      expect(notifications.local.scheduled, hasLength(1));
      expect(notifications.local.scheduled.values.single.fireAt, later);
    });

    test(
      'moving the date reopens a completed reminder and drops a snooze',
      () async {
        await create();
        final Reminder saved = finance.reminders.single;
        await controller.complete(saved);
        expect(finance.reminders.single.isCompleted, isTrue);

        await controller.saveReminder(
          id: saved.id,
          existing: finance.reminders.single,
          type: ReminderType.payment,
          title: saved.title,
          description: null,
          amount: null,
          contactId: null,
          transactionId: null,
          remindAt: soon(9),
          repeat: ReminderRepeat.none,
          notificationEnabled: true,
        );
        expect(finance.reminders.single.isCompleted, isFalse);
        expect(notifications.local.scheduled, hasLength(1));
      },
    );

    test('editing only the title keeps a snooze in place', () async {
      await create();
      final Reminder saved = finance.reminders.single;
      await controller.snooze(saved, SnoozeOption.oneHour);
      final Reminder snoozed = finance.reminders.single;
      expect(snoozed.snoozedUntil, isNotNull);

      await controller.saveReminder(
        id: saved.id,
        existing: snoozed,
        type: saved.type,
        title: 'Renamed',
        description: null,
        amount: null,
        contactId: null,
        transactionId: null,
        remindAt: snoozed.remindAt,
        repeat: snoozed.repeat,
        notificationEnabled: true,
      );
      expect(finance.reminders.single.snoozedUntil, snoozed.snoozedUntil);
    });
  });

  group('deletion', () {
    test('removes the reminder and cancels its notification', () async {
      await create();
      final String id = finance.reminders.single.id;
      expect(notifications.local.scheduled, hasLength(1));

      expect(await controller.deleteReminder(id), isTrue);
      expect(finance.reminders, isEmpty);
      expect(controller.reminders, isEmpty);
      expect(notifications.local.scheduled, isEmpty);
    });

    test('only the deleted reminder is cancelled', () async {
      await create();
      await create(id: 'a1b2c3d4-0000-4000-8000-000000000002', title: 'Phone');
      await controller.deleteReminder('a1b2c3d4-0000-4000-8000-000000000001');
      expect(notifications.local.scheduled.keys, <int>[
        NotificationIds.forReminder('a1b2c3d4-0000-4000-8000-000000000002'),
      ]);
    });

    test('a failed delete keeps the reminder and says why', () async {
      await create();
      finance.nextError = const NetworkFailure();
      expect(
        await controller.deleteReminder(finance.reminders.single.id),
        isFalse,
      );
      expect(controller.deletion.error.value, isNotNull);
      expect(finance.reminders, hasLength(1));
    });
  });

  group('complete, snooze, enable', () {
    test('completing a one-time reminder cancels its notification', () async {
      await create();
      expect(await controller.complete(finance.reminders.single), isTrue);
      expect(finance.reminders.single.isCompleted, isTrue);
      expect(notifications.local.scheduled, isEmpty);
    });

    test(
      'completing a repeating reminder schedules the next occurrence',
      () async {
        await create(repeat: ReminderRepeat.daily, at: soon(1));
        final Reminder before = finance.reminders.single;
        await controller.complete(before);
        final Reminder after = finance.reminders.single;
        expect(after.isCompleted, isFalse);
        expect(after.remindAt.isAfter(before.remindAt), isTrue);
        expect(notifications.local.scheduled, hasLength(1));
        expect(
          notifications.local.scheduled.values.single.fireAt,
          after.remindAt,
        );
      },
    );

    test('mark as not done brings a completed reminder back', () async {
      await create();
      await controller.complete(finance.reminders.single);
      await controller.reopen(finance.reminders.single);
      expect(finance.reminders.single.isCompleted, isFalse);
      expect(notifications.local.scheduled, hasLength(1));
    });

    test('snoozing reschedules the notification for the snooze time', () async {
      await create(repeat: ReminderRepeat.weekly);
      final DateTime before = DateTime.now();
      await controller.snooze(
        finance.reminders.single,
        SnoozeOption.threeHours,
      );

      final DateTime until = finance.reminders.single.snoozedUntil!;
      expect(until.difference(before).inMinutes, inInclusiveRange(179, 181));
      final PlannedNotification planned =
          notifications.local.scheduled.values.single;
      expect(planned.fireAt, until);
      expect(planned.repeat, ReminderRepeat.none);
      expect(
        controller.sections().single.reminders.single.id,
        finance.reminders.single.id,
        reason: 'a snoozed reminder is still listed as upcoming',
      );
    });

    test('disabling and enabling toggles the notification', () async {
      await create();
      await controller.setNotificationEnabled(finance.reminders.single, false);
      expect(finance.reminders.single.notificationEnabled, isFalse);
      expect(notifications.local.scheduled, isEmpty);

      await controller.setNotificationEnabled(finance.reminders.single, true);
      expect(notifications.local.scheduled, hasLength(1));
    });

    test('a failed action reports the error and changes nothing', () async {
      await create();
      finance.nextError = const NetworkFailure();
      expect(await controller.complete(finance.reminders.single), isFalse);
      expect(controller.action.error.value, isNotNull);
      expect(finance.reminders.single.isCompleted, isFalse);
    });
  });

  group('list', () {
    test('groups into overdue, upcoming and completed', () async {
      final DateTime now = DateTime.now();
      finance.reminders.addAll(<Reminder>[
        makeReminder(
          id: 'a1b2c3d4-0000-4000-8000-000000000001',
          title: 'Old',
          remindAt: now.subtract(const Duration(days: 2)),
        ),
        makeReminder(
          id: 'a1b2c3d4-0000-4000-8000-000000000002',
          title: 'Soon',
          remindAt: now.add(const Duration(days: 1)),
        ),
        makeReminder(
          id: 'a1b2c3d4-0000-4000-8000-000000000003',
          title: 'Later',
          remindAt: now.add(const Duration(days: 9)),
        ),
        makeReminder(
          id: 'a1b2c3d4-0000-4000-8000-000000000004',
          title: 'Done',
          remindAt: now.subtract(const Duration(days: 5)),
          isCompleted: true,
        ),
      ]);
      await controller.load();

      final List<ReminderSection> sections = controller.sections();
      expect(sections.map((ReminderSection s) => s.title).toList(), <String>[
        'Overdue',
        'Upcoming',
        'Completed',
      ]);
      expect(
        sections[1].reminders.map((Reminder r) => r.title).toList(),
        <String>['Soon', 'Later'],
        reason: 'soonest first',
      );
    });

    test(
      'is empty with no reminders and a load failure sets the error',
      () async {
        expect(controller.sections(), isEmpty);
        finance.nextError = const NetworkFailure();
        await controller.load();
        expect(controller.error.value, isNotNull);
        expect(controller.isLoading.value, isFalse);
      },
    );

    test(
      'overdue reminders are recorded in the notification center once',
      () async {
        finance.reminders.add(
          makeReminder(
            remindAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
        );
        await controller.load();
        await controller.load();
        expect(finance.notifications, hasLength(1));
      },
    );
  });

  group('permission', () {
    test('the first save with notifications on asks once', () async {
      await setUpController(granted: false);
      expect(notifications.coordinator.permission.value.canPrompt, isTrue);

      await create();
      expect(notifications.local.promptCount, 1);
      await create(id: 'a1b2c3d4-0000-4000-8000-000000000002');
      expect(
        notifications.local.promptCount,
        1,
        reason: 'granted at the prompt',
      );
    });

    test('saving after a refusal never prompts again', () async {
      await setUpController(granted: false);
      notifications.local.promptGrants = false;
      await create();
      expect(
        notifications.coordinator.permission.value,
        NotificationPermissionState.blocked,
      );
      await create(id: 'a1b2c3d4-0000-4000-8000-000000000002');
      await create(id: 'a1b2c3d4-0000-4000-8000-000000000003');
      expect(notifications.local.promptCount, 1);
      expect(finance.reminders, hasLength(3), reason: 'still saved');
    });

    test('a reminder with notify off never prompts', () async {
      await setUpController(granted: false);
      await create(notify: false);
      expect(notifications.local.promptCount, 0);
    });
  });

  group('khata prefill', () {
    test('receivable when the contact owes the user', () {
      final ReminderFormArgs args = ReminderFormArgs.forContact(
        contactId: 'c-1',
        balance: Decimal.parse('2500'),
      );
      expect(args.type, ReminderType.receivable);
      expect(args.amount, Decimal.parse('2500'));
      expect(args.contactId, 'c-1');
    });

    test('payable when the user owes the contact, with a positive amount', () {
      final ReminderFormArgs args = ReminderFormArgs.forContact(
        contactId: 'c-1',
        balance: Decimal.parse('-400'),
      );
      expect(args.type, ReminderType.payable);
      expect(args.amount, Decimal.parse('400'));
    });

    test(
      'plain khata reminder when settled, and no name or figure in the title',
      () {
        final ReminderFormArgs settled = ReminderFormArgs.forContact(
          contactId: 'c-1',
          balance: Decimal.zero,
        );
        expect(settled.type, ReminderType.khata);
        expect(settled.amount, isNull);
        for (final String balance in <String>['2500', '-400', '0']) {
          final String title = ReminderFormArgs.forContact(
            contactId: 'c-1',
            balance: Decimal.parse(balance),
          ).title!;
          expect(title, isNot(matches(RegExp(r'\d'))));
        }
      },
    );
  });
}
