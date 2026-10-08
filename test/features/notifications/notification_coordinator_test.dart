import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/services/notification_permission_state.dart';
import 'package:finance_tracker/core/services/push_service.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_notification_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fake_notifications.dart';
import '../../helpers/fakes.dart';
import '../../helpers/reminder_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFinance finance;
  late FakeAuthRepository auth;

  setUp(() {
    finance = FakeFinance();
    auth = FakeAuthRepository(signedIn: true);
  });

  Future<NotificationsHandle> start({
    bool granted = false,
    bool promptGrants = true,
    bool pushAvailable = false,
    StorageService? storage,
  }) async {
    final NotificationsHandle h = await buildCoordinator(
      finance,
      auth: auth,
      local: FakeLocalNotifications(
        granted: granted,
        promptGrants: promptGrants,
      ),
      push: FakePush(available: pushAvailable),
      storage: storage,
    );
    await h.coordinator.initialize();
    return h;
  }

  Reminder inDays(
    int days, {
    String id = 'a1b2c3d4-0000-4000-8000-000000000001',
  }) => makeReminder(
    id: id,
    remindAt: DateTime.now().add(Duration(days: days)),
  );

  group('permission', () {
    test('starts denied (promptable) when never asked', () async {
      final NotificationsHandle h = await start();
      expect(
        h.coordinator.permission.value,
        NotificationPermissionState.denied,
      );
      expect(h.local.promptCount, 0, reason: 'nothing is asked on startup');
    });

    test('is granted when the OS already allows notifications', () async {
      final NotificationsHandle h = await start(granted: true);
      expect(
        h.coordinator.permission.value,
        NotificationPermissionState.granted,
      );
    });

    test(
      'asks once; after a refusal it is blocked and never asks again',
      () async {
        final NotificationsHandle h = await start(promptGrants: false);

        expect(await h.coordinator.requestPermission(), isFalse);
        expect(h.local.promptCount, 1);
        expect(
          h.coordinator.permission.value,
          NotificationPermissionState.blocked,
        );

        expect(await h.coordinator.requestPermission(), isFalse);
        expect(h.local.promptCount, 1, reason: 'no second prompt');
      },
    );

    test('the refusal is remembered across restarts', () async {
      final StorageService storage = await memoryStorage();
      final NotificationsHandle first = await start(
        promptGrants: false,
        storage: storage,
      );
      await first.coordinator.requestPermission();

      final NotificationsHandle second = await start(storage: storage);
      expect(
        second.coordinator.permission.value,
        NotificationPermissionState.blocked,
      );
    });

    test(
      'granting at the prompt turns notifications on and schedules',
      () async {
        final NotificationsHandle h = await start();
        await h.coordinator.syncReminders(<Reminder>[inDays(1)]);
        expect(await h.coordinator.requestPermission(), isTrue);
        expect(
          h.coordinator.permission.value,
          NotificationPermissionState.granted,
        );
        expect(h.local.scheduled, hasLength(1));
      },
    );

    test('settings can be opened for a blocked permission', () async {
      final NotificationsHandle h = await start(promptGrants: false);
      await h.coordinator.requestPermission();
      await h.coordinator.openSettings();
      expect(h.local.settingsOpened, 1);
    });

    test(
      'a platform without notifications is reported as unsupported',
      () async {
        final NotificationsHandle h = await buildCoordinator(
          finance,
          auth: auth,
          local: FakeLocalNotifications(supported: false),
        );
        await h.coordinator.initialize();
        expect(
          h.coordinator.permission.value,
          NotificationPermissionState.unsupported,
        );
        expect(await h.coordinator.requestPermission(), isFalse);
        expect(h.local.promptCount, 0);
      },
    );
  });

  group('scheduling', () {
    test('schedules each reminder under its stable id', () async {
      final NotificationsHandle h = await start(granted: true);
      final Reminder r = inDays(2);
      await h.coordinator.syncReminders(<Reminder>[r]);
      expect(h.local.scheduled.keys, <int>[NotificationIds.forReminder(r.id)]);
      expect(h.local.scheduled.values.single.payload, 'reminder:${r.id}');
    });

    test('syncing again never creates a second notification', () async {
      final NotificationsHandle h = await start(granted: true);
      final List<Reminder> reminders = <Reminder>[
        inDays(2),
        inDays(3, id: 'a1b2c3d4-0000-4000-8000-000000000002'),
      ];
      for (int i = 0; i < 4; i++) {
        await h.coordinator.syncReminders(reminders);
      }
      expect(h.local.scheduled, hasLength(2));
    });

    test('overlapping syncs are folded into one consistent result', () async {
      final NotificationsHandle h = await start(granted: true);
      final Reminder a = inDays(2);
      final Reminder b = inDays(3, id: 'a1b2c3d4-0000-4000-8000-000000000002');
      // Fired without awaiting, as quick successive edits would be.
      final List<Future<void>> runs = <Future<void>>[
        h.coordinator.syncReminders(<Reminder>[a]),
        h.coordinator.syncReminders(<Reminder>[a, b]),
        h.coordinator.syncReminders(<Reminder>[b]),
      ];
      await Future.wait(runs);
      // The last request wins and nothing from earlier ones lingers.
      expect(h.local.scheduled.keys, <int>[NotificationIds.forReminder(b.id)]);
      expect(h.local.syncCalls, lessThanOrEqualTo(3));
    });

    test('a removed, completed or disabled reminder is cancelled', () async {
      final NotificationsHandle h = await start(granted: true);
      final Reminder a = inDays(2);
      final Reminder b = inDays(3, id: 'a1b2c3d4-0000-4000-8000-000000000002');
      await h.coordinator.syncReminders(<Reminder>[a, b]);
      expect(h.local.scheduled, hasLength(2));

      await h.coordinator.syncReminders(<Reminder>[
        a.copyWith(isCompleted: true),
        b,
      ]);
      expect(h.local.scheduled.keys, <int>[NotificationIds.forReminder(b.id)]);

      await h.coordinator.syncReminders(<Reminder>[
        b.copyWith(notificationEnabled: false),
      ]);
      expect(h.local.scheduled, isEmpty);
    });

    test(
      'a due-but-undelivered alarm survives a resync, an old one rolls on',
      () async {
        final NotificationsHandle h = await start(granted: true);
        final DateTime now = DateTime.now();
        final Reminder justDue = makeReminder(
          id: 'a1b2c3d4-0000-4000-8000-000000000001',
          remindAt: now.subtract(const Duration(minutes: 2)),
          repeat: ReminderRepeat.daily,
        );
        final Reminder longAgo = makeReminder(
          id: 'a1b2c3d4-0000-4000-8000-000000000002',
          remindAt: now.subtract(const Duration(hours: 3)),
          repeat: ReminderRepeat.daily,
        );
        // The OS still holds today's alarm for both (it has not fired yet).
        for (final Reminder r in <Reminder>[justDue, longAgo]) {
          h.local.scheduled[NotificationIds.forReminder(
            r.id,
          )] = PlannedNotification(
            id: NotificationIds.forReminder(r.id),
            title: r.title,
            body: 'old',
            payload: 'reminder:${r.id}',
            fireAt: r.remindAt,
            repeat: r.repeat,
          );
        }

        await h.coordinator.syncReminders(<Reminder>[justDue, longAgo]);

        final PlannedNotification kept =
            h.local.scheduled[NotificationIds.forReminder(justDue.id)]!;
        expect(kept.body, 'old', reason: 'left exactly as the OS has it');
        final PlannedNotification rolled =
            h.local.scheduled[NotificationIds.forReminder(longAgo.id)]!;
        expect(rolled.fireAt.isAfter(now), isTrue, reason: 'next occurrence');
      },
    );

    test(
      'an in-flight alarm is still cancelled when its reminder is done',
      () async {
        final NotificationsHandle h = await start(granted: true);
        final Reminder justDue = makeReminder(
          remindAt: DateTime.now().subtract(const Duration(minutes: 2)),
        );
        final int id = NotificationIds.forReminder(justDue.id);
        h.local.scheduled[id] = PlannedNotification(
          id: id,
          title: 't',
          body: 'b',
          payload: 'p',
          fireAt: justDue.remindAt,
          repeat: ReminderRepeat.none,
        );
        await h.coordinator.syncReminders(<Reminder>[
          justDue.copyWith(isCompleted: true),
        ]);
        expect(h.local.scheduled, isEmpty);
      },
    );

    test(
      'turning notifications off cancels everything, on brings it back',
      () async {
        final NotificationsHandle h = await start(granted: true);
        await h.coordinator.syncReminders(<Reminder>[inDays(2)]);
        expect(h.local.scheduled, hasLength(1));

        await h.coordinator.updatePreferences(
          h.coordinator.preferences.value.copyWith(enabled: false),
        );
        expect(h.local.scheduled, isEmpty);

        await h.coordinator.updatePreferences(
          h.coordinator.preferences.value.copyWith(enabled: true),
        );
        expect(h.local.scheduled, hasLength(1));
      },
    );

    test(
      'turning reminders off cancels them but keeps other alerts on',
      () async {
        final NotificationsHandle h = await start(granted: true);
        await h.coordinator.syncReminders(<Reminder>[inDays(2)]);
        await h.coordinator.updatePreferences(
          h.coordinator.preferences.value.copyWith(reminders: false),
        );
        expect(h.local.scheduled, isEmpty);
        expect(
          h.coordinator.preferences.value.allows(NotificationType.budgetAlert),
          isTrue,
        );
      },
    );

    test(
      'turning notifications on asks for permission once, not before',
      () async {
        final NotificationsHandle h = await start();
        await h.coordinator.updatePreferences(
          h.coordinator.preferences.value.copyWith(enabled: false),
        );
        expect(h.local.promptCount, 0);
        await h.coordinator.updatePreferences(
          h.coordinator.preferences.value.copyWith(enabled: true),
        );
        expect(h.local.promptCount, 1);
      },
    );

    test('preferences survive a restart', () async {
      final StorageService storage = await memoryStorage();
      final NotificationsHandle first = await start(storage: storage);
      await first.coordinator.updatePreferences(
        const NotificationPreferences(budgets: false, sound: false),
      );
      final NotificationsHandle second = await start(storage: storage);
      expect(second.coordinator.preferences.value.budgets, isFalse);
      expect(second.coordinator.preferences.value.sound, isFalse);
      expect(second.coordinator.preferences.value.reminders, isTrue);
    });
  });

  group('raising notifications', () {
    Future<void> raiseBudget(NotificationCoordinator c, {String id = 'n-1'}) =>
        c.raise(
          id: id,
          type: NotificationType.budgetAlert,
          title: 'Food budget at 75%',
          body: 'You have spent ₹750.00 of ₹1,000.00.',
          referenceId: 'a1b2c3d4-0000-4000-8000-0000000000b1',
        );

    test('stores the entry once and shows it on the device once', () async {
      final NotificationsHandle h = await start(granted: true);
      await raiseBudget(h.coordinator);
      await raiseBudget(h.coordinator);
      await raiseBudget(h.coordinator);
      expect(finance.notifications, hasLength(1));
      expect(h.local.shown, hasLength(1));
    });

    test('the device text carries no amount, the stored entry does', () async {
      final NotificationsHandle h = await start(granted: true);
      await raiseBudget(h.coordinator);
      expect(finance.notifications['n-1']!['body'], contains('₹750.00'));
      expect(h.local.shown.single.body, isNot(contains('₹')));
      expect(h.local.shown.single.payload, startsWith('budget_alert:'));
    });

    test('is stored but not shown while permission is missing', () async {
      final NotificationsHandle h = await start();
      await raiseBudget(h.coordinator);
      expect(finance.notifications, hasLength(1));
      expect(h.local.shown, isEmpty);
    });

    test('nothing is raised for a kind the user turned off', () async {
      final NotificationsHandle h = await start(granted: true);
      await h.coordinator.updatePreferences(
        h.coordinator.preferences.value.copyWith(budgets: false),
      );
      await raiseBudget(h.coordinator);
      expect(finance.notifications, isEmpty);
      expect(h.local.shown, isEmpty);
    });

    test(
      'overdue reminders are recorded once, without a second device alert',
      () async {
        final NotificationsHandle h = await start(granted: true);
        final Reminder overdue = makeReminder(
          remindAt: DateTime.now().subtract(const Duration(hours: 2)),
          title: 'Pay rent',
        );
        await h.coordinator.raiseDueReminders(<Reminder>[overdue]);
        await h.coordinator.raiseDueReminders(<Reminder>[overdue]);
        expect(finance.notifications, hasLength(1));
        expect(finance.notifications.values.single['type'], 'reminder');
        expect(finance.notifications.values.single['reference_id'], overdue.id);
        expect(h.local.shown, isEmpty);
      },
    );

    test(
      'upcoming, completed and disabled reminders are not recorded',
      () async {
        final NotificationsHandle h = await start(granted: true);
        final DateTime past = DateTime.now().subtract(const Duration(hours: 2));
        await h.coordinator.raiseDueReminders(<Reminder>[
          inDays(1),
          makeReminder(remindAt: past, isCompleted: true),
          makeReminder(remindAt: past, notificationEnabled: false),
        ]);
        expect(finance.notifications, isEmpty);
      },
    );
  });

  group('session', () {
    test('signing out cancels every scheduled notification', () async {
      final NotificationsHandle h = await start(granted: true);
      await h.coordinator.syncReminders(<Reminder>[inDays(2)]);
      expect(h.local.scheduled, hasLength(1));

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(h.local.scheduled, isEmpty);
    });

    test(
      'registers the push token for a signed-in user with permission',
      () async {
        final NotificationsHandle h = await start(
          granted: true,
          pushAvailable: true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(finance.deviceTokens, hasLength(1));
        expect(finance.deviceTokens.values.single.token, 'token-1');
        expect(finance.deviceTokens.values.single.active, isTrue);
        expect(h.push.available, isTrue);
      },
    );

    test('does not register a token without permission', () async {
      await start(pushAvailable: true);
      await Future<void>.delayed(Duration.zero);
      expect(finance.deviceTokens, isEmpty);
    });

    test('a refreshed token replaces the old one for this device', () async {
      final NotificationsHandle h = await start(
        granted: true,
        pushAvailable: true,
      );
      await Future<void>.delayed(Duration.zero);
      h.push.currentToken = 'token-2';
      h.push.refreshes.add('token-2');
      await Future<void>.delayed(Duration.zero);
      expect(finance.deviceTokens, hasLength(1));
      expect(finance.deviceTokens.values.single.token, 'token-2');
    });

    test('sign-out stops pushes to this device first', () async {
      final NotificationsHandle h = await start(
        granted: true,
        pushAvailable: true,
      );
      await Future<void>.delayed(Duration.zero);
      await auth.signOut();
      expect(finance.deviceTokens.values.single.active, isFalse);
      expect(h.push.deletedTokens, 1);
    });

    test('a foreground push is shown as a local notification', () async {
      final NotificationsHandle h = await start(
        granted: true,
        pushAvailable: true,
      );
      h.push.foreground.add(
        const PushMessage(
          title: 'Budget alert',
          body: 'Open the app',
          data: <String, dynamic>{
            'type': 'budget_alert',
            'reference_id': 'a1b2c3d4-0000-4000-8000-0000000000b1',
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(h.local.shown, hasLength(1));
      expect(
        h.local.shown.single.payload,
        'budget_alert:a1b2c3d4-0000-4000-8000-0000000000b1',
      );
    });

    test('a foreground push is dropped when notifications are off', () async {
      final NotificationsHandle h = await start(
        granted: true,
        pushAvailable: true,
      );
      await h.coordinator.updatePreferences(
        h.coordinator.preferences.value.copyWith(enabled: false),
      );
      h.push.foreground.add(const PushMessage(title: 'Hi'));
      await Future<void>.delayed(Duration.zero);
      expect(h.local.shown, isEmpty);
    });
  });
}
