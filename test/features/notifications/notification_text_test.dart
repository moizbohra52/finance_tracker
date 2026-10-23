import 'package:finance_tracker/core/translations/app_translations.dart';
import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:finance_tracker/domain/services/reminder_notification_planner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fake_notifications.dart';
import '../../helpers/fakes.dart';
import '../../helpers/reminder_fixtures.dart';

/// What a notification says is fixed when it is scheduled or shown, so it must
/// be in the app language then, and follow a change of language.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFinance finance;
  late NotificationsHandle h;

  setUp(() async {
    Get.addTranslations(AppTranslations().keys);
    finance = FakeFinance();
    h = await buildCoordinator(
      finance,
      auth: FakeAuthRepository(signedIn: true),
      local: FakeLocalNotifications(granted: true),
    );
    await h.coordinator.initialize();
  });

  tearDown(() => Get.locale = AppLanguage.english.locale);

  Reminder upcoming() => makeReminder(
    type: ReminderType.receivable,
    remindAt: DateTime.now().add(const Duration(days: 1)),
  );

  String scheduledBody() => h.local.scheduled.values.single.body;

  test('a scheduled reminder says its kind in the app language', () async {
    Get.locale = AppLanguage.hindi.locale;
    await h.coordinator.syncReminders(<Reminder>[upcoming()]);

    expect(scheduledBody(), hindi['Money to collect']);
  });

  test('changing the language reschedules the reminders', () async {
    await h.coordinator.syncReminders(<Reminder>[upcoming()]);
    expect(scheduledBody(), 'Money to collect');

    Get.locale = AppLanguage.hindi.locale;
    await h.coordinator.languageChanged();

    expect(scheduledBody(), hindi['Money to collect']);
  });

  test(
    'a language change before any reminders are known cancels nothing',
    () async {
      await h.coordinator.languageChanged();

      expect(h.local.syncCalls, 0);
    },
  );

  test('a stored due-reminder entry is in the app language', () async {
    Get.locale = AppLanguage.hindi.locale;
    final Reminder overdue = makeReminder(
      type: ReminderType.payable,
      remindAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

    await h.coordinator.raiseDueReminders(<Reminder>[overdue]);

    expect(finance.notifications.values.single['body'], hindi['Money to pay']);
  });

  test('the text shown on the device is in the app language', () async {
    Get.locale = AppLanguage.hindi.locale;
    await h.coordinator.raise(
      id: 'e1',
      type: NotificationType.budgetAlert,
      title: 'x',
      body: 'x',
      referenceId: 'b1',
    );

    expect(
      h.local.shown.single.body,
      hindi['Open the app to see your budget.'],
    );
  });

  test('the buttons on a reminder notification have Hindi labels', () {
    Get.locale = AppLanguage.hindi.locale;

    for (final ReminderAction action in ReminderAction.values) {
      expect(action.label.tr, hindi[action.label], reason: action.name);
    }
  });

  test('the background isolate takes the language this device last used', () {
    AppTranslations.use(AppLanguage.hindi);

    expect('Money to collect'.tr, hindi['Money to collect']);
    expect(Get.locale, AppLanguage.hindi.locale);
  });

  test('English stays the default text', () {
    expect(
      ReminderNotificationPlanner.bodyFor(ReminderType.receivable),
      'Money to collect',
    );
  });
}
