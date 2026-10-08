import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/features/budgets/views/budget_list_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_detail_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_entry_view.dart';
import 'package:finance_tracker/features/dashboard/views/app_shell_view.dart';
import 'package:finance_tracker/features/notifications/views/notification_center_view.dart';
import 'package:finance_tracker/features/reminders/views/reminder_detail_view.dart';
import 'package:finance_tracker/features/reminders/views/reminder_form_view.dart';
import 'package:finance_tracker/features/reminders/views/reminder_list_view.dart';
import 'package:finance_tracker/features/settings/views/settings_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/contact_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fake_notifications.dart';
import '../../helpers/fakes.dart';
import '../../helpers/reminder_fixtures.dart';

const String _contactId = 'a1b2c3d4-0000-4000-8000-0000000000c1';
const String _reminderId = 'a1b2c3d4-0000-4000-8000-0000000000a1';
const String _budgetId = 'a1b2c3d4-0000-4000-8000-0000000000b1';

Contact _contact() => Contact(
  id: _contactId,
  userId: 'u',
  name: 'Asha Rao',
  openingBalance: Decimal.zero,
  openingBalanceType: 'receivable',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

FakeFinance _seeded() => FakeFinance()
  ..addAccount('Cash', '1000')
  ..contacts.add(_contact());

Reminder _reminder({
  String id = _reminderId,
  String title = 'Electricity bill',
  DateTime? at,
  ReminderType type = ReminderType.payment,
  String? contactId,
  ReminderRepeat repeat = ReminderRepeat.none,
  bool done = false,
}) => makeReminder(
  id: id,
  title: title,
  type: type,
  contactId: contactId,
  repeat: repeat,
  isCompleted: done,
  remindAt: at ?? DateTime.now().add(const Duration(days: 3)),
);

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Boots the signed-in app on fakes; the OS allows notifications unless told
/// otherwise.
Future<NotificationsHandle> _start(
  WidgetTester tester,
  FakeFinance finance, {
  bool granted = true,
  bool promptGrants = true,
  bool supported = true,
  String? launch,
  FakeAuthRepository? auth,
}) async {
  final FakeAuthRepository session = auth ?? FakeAuthRepository(signedIn: true);
  final NotificationsHandle handle = await buildCoordinator(
    finance,
    auth: session,
    local: FakeLocalNotifications(
      granted: granted,
      promptGrants: promptGrants,
      supported: supported,
    )..launch = launch,
  );
  await pumpApp(tester, auth: session, finance: finance, notifications: handle);
  return handle;
}

Future<void> _tapNav(WidgetTester tester, IconData icon) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(icon),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens a route directly, as a notification or deep link would.
Future<void> _go(WidgetTester tester, String route, [Object? arguments]) async {
  unawaited_(Get.toNamed<void>(route, arguments: arguments));
  await tester.pumpAndSettle();
}

void unawaited_(Future<void>? future) {}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextFormField>(_field(label)).controller!.text;

void main() {
  tearDown(Get.reset);

  group('khata to notification', () {
    testWidgets(
      'credit, add reminder, schedule, tap the notification, open the contact',
      (WidgetTester tester) async {
        await _tall(tester);
        final FakeFinance f = _seeded();
        final NotificationsHandle h = await _start(tester, f);

        // Khata contact -> create credit.
        await _tapNav(tester, Icons.people_outline);
        await tester.tap(find.widgetWithText(ContactBalanceTile, 'Asha Rao'));
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Add credit'));
        expect(find.byType(ContactEntryView), findsOneWidget);
        await tester.enterText(_field('Amount'), '500');
        await tapAndSettle(
          tester,
          find.widgetWithText(FilledButton, 'Save credit'),
        );
        expect(find.byType(ContactDetailView), findsOneWidget);
        expect(find.text('You will get'), findsOneWidget);

        // -> Add reminder, prefilled from the contact and the balance.
        await tester.tap(find.byTooltip('Add reminder'));
        await tester.pumpAndSettle();
        expect(find.byType(ReminderFormView), findsOneWidget);
        expect(_text(tester, 'Title'), 'Collect payment');
        expect(_text(tester, 'Amount (optional)'), '500');
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Receivable'))
              .selected,
          isTrue,
        );
        expect(find.text('Asha Rao'), findsOneWidget);

        // -> Schedule notification.
        await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
        expect(find.byType(ContactDetailView), findsOneWidget);
        expect(find.text('Reminder added'), findsOneWidget);

        final Reminder saved = f.reminders.single;
        expect(saved.type, ReminderType.receivable);
        expect(saved.contactId, _contactId);
        expect(saved.amount, Decimal.parse('500'));
        expect(saved.remindAt.isAfter(DateTime.now()), isTrue);
        expect(h.local.scheduled, hasLength(1));
        final planned = h.local.scheduled.values.single;
        expect(planned.fireAt, saved.remindAt);

        // The text on the lock screen carries no name and no amount.
        expect(planned.title, 'Collect payment');
        expect('${planned.title} ${planned.body}', isNot(contains('Asha')));
        expect('${planned.title} ${planned.body}', isNot(contains('500')));

        // -> Notification appears, user taps it -> reminder.
        h.local.tap(planned.payload);
        await tester.pumpAndSettle();
        expect(find.byType(ReminderDetailView), findsOneWidget);
        expect(find.text('Collect payment'), findsOneWidget);
        expect(find.text('Upcoming'), findsOneWidget);

        // -> and from the reminder to the contact.
        await tapAndSettle(tester, find.text('Asha Rao'));
        expect(find.byType(ContactDetailView), findsOneWidget);
      },
    );

    testWidgets('a settled contact gets a plain khata reminder', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final NotificationsHandle h = await _start(tester, _seeded());
      await _tapNav(tester, Icons.people_outline);
      await tester.tap(find.widgetWithText(ContactBalanceTile, 'Asha Rao'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add reminder'));
      await tester.pumpAndSettle();
      expect(_text(tester, 'Title'), 'Khata follow-up');
      expect(_text(tester, 'Amount (optional)'), isEmpty);
      expect(h.local.scheduled, isEmpty);
    });
  });

  group('notification taps', () {
    testWidgets('a tap that launched the app opens its reminder', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      await _start(tester, f, launch: 'reminder:$_reminderId');

      expect(find.byType(ReminderDetailView), findsOneWidget);
      expect(find.text('Electricity bill'), findsOneWidget);

      // Back goes to the app, not out of it.
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(find.byType(AppShellView), findsOneWidget);
    });

    testWidgets('a tap while signed out waits for sign-in, then opens', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final FakeAuthRepository auth = FakeAuthRepository();
      await _start(tester, f, launch: 'reminder:$_reminderId', auth: auth);
      expect(find.byType(ReminderDetailView), findsNothing);

      auth.emit(AuthStatus.signedIn);
      await tester.pumpAndSettle();
      expect(find.byType(ReminderDetailView), findsOneWidget);
    });

    testWidgets('a tap while the app is open goes to the notification screen', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f);
      h.local.tap('reminder:$_reminderId');
      await tester.pumpAndSettle();
      expect(find.byType(ReminderDetailView), findsOneWidget);

      Get.back<void>();
      await tester.pumpAndSettle();
      h.local.tap('budget_alert:$_budgetId');
      await tester.pumpAndSettle();
      expect(find.byType(BudgetListView), findsOneWidget);
    });

    testWidgets('a payload that cannot be opened lands in the center', (
      WidgetTester tester,
    ) async {
      final NotificationsHandle h = await _start(tester, _seeded());
      h.local.tap('reminder:not-a-uuid');
      await tester.pumpAndSettle();
      expect(find.byType(NotificationCenterView), findsOneWidget);
    });

    testWidgets('a reminder that no longer exists says so', (
      WidgetTester tester,
    ) async {
      final NotificationsHandle h = await _start(tester, _seeded());
      h.local.tap('reminder:$_reminderId');
      await tester.pumpAndSettle();
      expect(find.text('Reminder not found'), findsOneWidget);
    });
  });

  group('reminder list', () {
    testWidgets('empty state leads to the form; saving lists and schedules', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded();
      final NotificationsHandle h = await _start(tester, f);
      await _go(tester, AppRoutes.reminders);
      expect(find.text('No reminders'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add reminder'));
      await tester.pumpAndSettle();
      expect(find.byType(ReminderFormView), findsOneWidget);

      // A title is required.
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(find.text('Enter your title'), findsOneWidget);
      expect(f.reminders, isEmpty);

      await tester.enterText(_field('Title'), 'Electricity bill');
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));

      expect(find.byType(ReminderListView), findsOneWidget);
      expect(find.text('Electricity bill'), findsOneWidget);
      expect(find.text('Upcoming'), findsWidgets);
      expect(f.reminders.single.title, 'Electricity bill');
      expect(h.local.scheduled, hasLength(1));
    });

    testWidgets('a contact is required for a khata type', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded();
      await _start(tester, f);
      await _go(tester, AppRoutes.reminderForm);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Payable'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Title'), 'Pay dues');
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(find.text('Choose who this is about'), findsOneWidget);
      expect(f.reminders, isEmpty);
    });

    testWidgets('groups reminders and shows their status', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()
        ..reminders.addAll(<Reminder>[
          _reminder(
            id: 'a1b2c3d4-0000-4000-8000-000000000011',
            title: 'Old bill',
            at: DateTime.now().subtract(const Duration(days: 2)),
          ),
          _reminder(
            id: 'a1b2c3d4-0000-4000-8000-000000000012',
            title: 'New bill',
          ),
          _reminder(
            id: 'a1b2c3d4-0000-4000-8000-000000000013',
            title: 'Paid bill',
            done: true,
            at: DateTime.now().subtract(const Duration(days: 9)),
          ),
        ]);
      await _start(tester, f);
      await _go(tester, AppRoutes.reminders);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Upcoming'), findsWidgets);
      expect(find.text('Completed'), findsWidgets);
      expect(find.text('Old bill'), findsOneWidget);
      expect(find.text('Paid bill'), findsOneWidget);
    });

    testWidgets('the switch on a row turns its notification off and on', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f);
      await _go(tester, AppRoutes.reminders);
      expect(h.local.scheduled, hasLength(1));

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(f.reminders.single.notificationEnabled, isFalse);
      expect(h.local.scheduled, isEmpty);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(h.local.scheduled, hasLength(1));
    });

    testWidgets('a load failure shows an error with retry', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      f.failAll = const NetworkFailure();
      await _start(tester, f);
      f.failAll = null;
      await _go(tester, AppRoutes.reminders);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Electricity bill'), findsOneWidget);
    });
  });

  group('reminder detail', () {
    testWidgets('mark as done cancels the notification, undo restores it', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f);
      await _go(tester, AppRoutes.reminderDetail, _reminderId);
      expect(h.local.scheduled, hasLength(1));

      await tapAndSettle(tester, find.text('Mark as done'));
      expect(f.reminders.single.isCompleted, isTrue);
      expect(find.text('Completed'), findsOneWidget);
      expect(h.local.scheduled, isEmpty);

      await tapAndSettle(tester, find.text('Mark as not done'));
      expect(f.reminders.single.isCompleted, isFalse);
      expect(h.local.scheduled, hasLength(1));
    });

    testWidgets('snooze moves the notification to the chosen time', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f);
      await _go(tester, AppRoutes.reminderDetail, _reminderId);

      await tapAndSettle(tester, find.text('Snooze'));
      expect(find.text('Remind me again in'), findsOneWidget);
      await tapAndSettle(tester, find.text('1 hour'));

      expect(find.text('Snoozed'), findsWidgets);
      final DateTime until = f.reminders.single.snoozedUntil!;
      expect(h.local.scheduled.values.single.fireAt, until);
      expect(
        until.difference(DateTime.now()).inMinutes,
        inInclusiveRange(58, 61),
      );
    });

    testWidgets('delete asks first, then removes and cancels', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f);
      await _go(tester, AppRoutes.reminders);
      await tester.tap(find.text('Electricity bill'));
      await tester.pumpAndSettle();
      expect(find.byType(ReminderDetailView), findsOneWidget);

      await tester.tap(find.byTooltip('Delete reminder'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this reminder?'), findsOneWidget);

      // Cancelling changes nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.reminders, hasLength(1));
      expect(h.local.scheduled, hasLength(1));

      await tester.tap(find.byTooltip('Delete reminder'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(f.reminders, isEmpty);
      expect(h.local.scheduled, isEmpty);
      expect(find.byType(ReminderListView), findsOneWidget);
    });

    testWidgets('edit changes the reminder and the schedule stays single', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f);
      await _go(tester, AppRoutes.reminderDetail, _reminderId);

      await tester.tap(find.byTooltip('Edit reminder'));
      await tester.pumpAndSettle();
      expect(_text(tester, 'Title'), 'Electricity bill');
      await tester.enterText(_field('Title'), 'Electricity bill (Oct)');
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Save changes'),
      );

      expect(f.reminders.single.title, 'Electricity bill (Oct)');
      expect(f.reminders, hasLength(1));
      expect(h.local.scheduled, hasLength(1));
      expect(h.local.scheduled.values.single.title, 'Electricity bill (Oct)');
    });
  });

  group('permission states', () {
    testWidgets('denied: explains once and offers Allow', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f, granted: false);
      await _go(tester, AppRoutes.reminders);

      expect(
        find.text('Allow notifications so reminders can alert you on time.'),
        findsOneWidget,
      );
      expect(
        h.local.promptCount,
        0,
        reason: 'showing the banner never prompts',
      );

      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(h.local.promptCount, 1);
      expect(find.text('Allow'), findsNothing);
    });

    testWidgets('blocked: points to system settings and does not prompt', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(
        tester,
        f,
        granted: false,
        promptGrants: false,
      );
      await h.coordinator.requestPermission();
      await _go(tester, AppRoutes.reminders);

      expect(find.textContaining('blocked for this app'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(h.local.settingsOpened, 1);
      expect(h.local.promptCount, 1);
    });

    testWidgets('notifications disabled in the app: banner offers Turn on', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f);
      await h.coordinator.updatePreferences(
        h.coordinator.preferences.value.copyWith(enabled: false),
      );
      await _go(tester, AppRoutes.reminders);
      expect(h.local.scheduled, isEmpty);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(h.coordinator.preferences.value.enabled, isTrue);
      expect(h.local.scheduled, hasLength(1));
    });

    testWidgets('granted: no banner', (WidgetTester tester) async {
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      await _start(tester, f);
      await _go(tester, AppRoutes.reminders);
      expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
    });

    testWidgets('unsupported platform: reminders work, no banner, no prompt', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f, supported: false);
      await _go(tester, AppRoutes.reminders);
      expect(find.text('Electricity bill'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
      expect(h.local.promptCount, 0);
    });
  });

  group('notification center', () {
    void seedRows(FakeFinance f) {
      f.notifications['n-1'] = <String, String>{
        'type': 'budget_alert',
        'title': 'Food budget at 75%',
        'body': 'You have spent ₹750.00 of ₹1,000.00.',
        'reference_id': _budgetId,
      };
      f.notifications['n-2'] = <String, String>{
        'type': 'reminder',
        'title': 'Electricity bill',
        'body': 'Payment reminder',
        'reference_id': _reminderId,
      };
    }

    testWidgets('the bell shows the unread count and opens the center', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      seedRows(f);
      await _start(tester, f);

      expect(find.byTooltip('Notifications, 2 unread'), findsOneWidget);
      await tester.tap(find.byTooltip('Notifications, 2 unread'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationCenterView), findsOneWidget);
      expect(find.text('Food budget at 75%'), findsOneWidget);
      expect(find.text('Electricity bill'), findsOneWidget);
    });

    testWidgets('tapping an entry marks it read and opens its screen', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      seedRows(f);
      await _start(tester, f);
      await _go(tester, AppRoutes.notifications);

      await tester.tap(find.text('Electricity bill'));
      await tester.pumpAndSettle();
      expect(find.byType(ReminderDetailView), findsOneWidget);
      expect(f.notifications['n-2']!['read_at'], isNotNull);
      expect(f.notifications['n-1']!['read_at'], isNull);

      Get.back<void>();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food budget at 75%'));
      await tester.pumpAndSettle();
      expect(find.byType(BudgetListView), findsOneWidget);
    });

    testWidgets('mark all as read clears the badge', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = _seeded();
      seedRows(f);
      await _start(tester, f);
      await _go(tester, AppRoutes.notifications);

      await tester.tap(find.byTooltip('Mark all as read'));
      await tester.pumpAndSettle();
      expect(
        f.notifications.values.every(
          (Map<String, String> r) => r['read_at'] != null,
        ),
        isTrue,
      );
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Notifications'), findsOneWidget);
    });

    testWidgets('empty and error states', (WidgetTester tester) async {
      final FakeFinance f = _seeded();
      f.failAll = const NetworkFailure();
      await _start(tester, f);
      f.failAll = null;
      await _go(tester, AppRoutes.notifications);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('You are all caught up'), findsOneWidget);
    });

    testWidgets('pages in more when there are many', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded();
      for (int i = 0; i < 40; i++) {
        f.notifications['n-$i'] = <String, String>{
          'type': 'recurring',
          'title': 'Entry $i',
          'body': 'Added automatically.',
          'reference_id': _budgetId,
        };
      }
      await _start(tester, f);
      await _go(tester, AppRoutes.notifications);
      expect(find.text('Entry 39'), findsOneWidget);
      expect(find.text('Entry 0'), findsNothing);

      await tester.scrollUntilVisible(find.text('Load more'), 300);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Entry 0'), 300);
      expect(find.text('Entry 0'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });
  });

  group('settings', () {
    testWidgets('switches change what is allowed, and persist', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      final FakeFinance f = _seeded()..reminders.add(_reminder());
      final NotificationsHandle h = await _start(tester, f);
      await _go(tester, AppRoutes.settings);
      expect(find.byType(SettingsView), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Budget alerts'), 200);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Budget alerts'));
      await tester.pumpAndSettle();
      expect(h.coordinator.preferences.value.budgets, isFalse);
      expect(h.coordinator.preferences.value.reminders, isTrue);
      expect(h.storage.readBool('notifications.budgets'), isFalse);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Reminders'));
      await tester.pumpAndSettle();
      expect(h.local.scheduled, isEmpty);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Notifications'));
      await tester.pumpAndSettle();
      expect(h.coordinator.preferences.value.enabled, isFalse);
      // Sub-switches are disabled while everything is off.
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Sound'),
            )
            .onChanged,
        isNull,
      );
    });

    testWidgets('says so on a platform without notifications', (
      WidgetTester tester,
    ) async {
      await _tall(tester);
      await _start(tester, _seeded(), supported: false);
      await _go(tester, AppRoutes.settings);
      await tester.scrollUntilVisible(
        find.textContaining('not available'),
        200,
      );
      expect(find.byType(SwitchListTile), findsNothing);
    });
  });
}
