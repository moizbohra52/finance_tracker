import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:ui';

import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/core/services/local_notification_service.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/translations/app_translations.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:finance_tracker/domain/services/reminder_notification_planner.dart';
import 'package:finance_tracker/features/notifications/notification_target.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _appPort = 'reminder_actions';

/// Calls [onChange] in the app's isolate whenever a notification button
/// changed a reminder, so open screens reload and the change gets synced.
void listenForReminderActions(void Function() onChange) {
  final ReceivePort port = ReceivePort();
  // A hot restart leaves the previous isolate's port registered.
  IsolateNameServer.removePortNameMapping(_appPort);
  IsolateNameServer.registerPortWithName(port.sendPort, _appPort);
  port.listen((_) => onChange());
}

/// Mark done (Paid, for a loan reminder) / Snooze tapped on a reminder
/// notification. The plugin runs this in a background isolate, whether or not
/// the app is open, so no app service exists here: the change goes through the
/// reminder's own account database and sync queue, exactly as the app writes
/// it, and only that reminder's device notification is rescheduled.
@pragma('vm:entry-point')
Future<void> reminderActionInBackground(NotificationResponse response) async {
  final ReminderAction? action = ReminderAction.values
      .asNameMap()[response.actionId];
  final String? owner = NotificationTarget.ownerOf(response.payload);
  final NotificationTarget? target = NotificationTarget.fromPayload(
    response.payload,
  );
  final String? reminderId = target?.reminderId;
  if (action == null || owner == null || reminderId == null) return;
  try {
    final Reminder? changed = await _save(action, owner, reminderId);
    if (changed == null) return;
    IsolateNameServer.lookupPortByName(_appPort)?.send(null);
    await _reschedule(changed, owner);
  } on Object catch (error) {
    developer.log(
      'Reminder notification action failed: ${error.runtimeType}',
      name: 'notifications',
    );
  }
}

/// The reminder after [action], saved; null when there is nothing to change
/// (account no longer on this device, reminder deleted or already done).
Future<Reminder?> _save(
  ReminderAction action,
  String owner,
  String reminderId,
) async {
  final String path = p.join(
    await getDatabasesPath(),
    AppDatabase.fileNameFor(owner),
  );
  if (!await databaseExists(path)) return null;
  // A connection of its own: sqflite shares single instances across isolates,
  // and closing that one would close the app's.
  final Database db = await openDatabase(path, singleInstance: false);
  // Only the local database is used: this client never connects, and keeps
  // no refresh timer alive in this isolate.
  final SupabaseClient client = SupabaseClient(
    AppEnv.supabaseUrl,
    AppEnv.supabasePublishableKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  try {
    final AppDatabase database = AppDatabase(database: db);
    // Paying a loan writes the reminder's title, so the text needs the
    // language this device last used (see [_reschedule]).
    await _loadStorage();
    return await applyReminderAction(
      reminders: ReminderRepository(client, database: database),
      loans: LoanRepository(database),
      action: action,
      reminderId: reminderId,
    );
  } finally {
    await db.close();
    await client.dispose();
  }
}

/// The reminder after [action], saved; null when there is nothing to change
/// (reminder deleted or already done, or a loan reminder that already moved).
///
/// Done on a loan reminder records the instalment that is due through
/// [LoanRepository.recordDuePayment], and the loan moves the reminder (or
/// removes it when that closed the loan, which comes back as a completed
/// copy so its notification is cancelled). A notification exists only for a
/// due date that has come and a recorded instalment moves the reminder to a
/// later one, so a reminder still in the future means this tap was already
/// handled (the same tap delivered twice): nothing is recorded again. With
/// nothing due the reminder is completed as for any other.
Future<Reminder?> applyReminderAction({
  required ReminderRepository reminders,
  required LoanRepository loans,
  required ReminderAction action,
  required String reminderId,
  DateTime? now,
}) async {
  final DateTime at = now ?? DateTime.now();
  Future<Reminder?> find() async => (await reminders.getAll())
      .where((Reminder r) => r.id == reminderId)
      .firstOrNull;
  final Reminder? reminder = await find();
  if (reminder == null || reminder.isCompleted) return null;
  final String? loanId = reminder.loanId;
  if (action == ReminderAction.done && loanId != null) {
    if (reminder.remindAt.isAfter(at)) return null;
    final LoanPayment? paid = await loans.recordDuePayment(loanId, now: at);
    if (paid != null) {
      return await find() ?? reminder.copyWith(isCompleted: true);
    }
  }
  final Reminder changed = ReminderCalculator.applyAction(reminder, action, at);
  await reminders.update(changed);
  return changed;
}

/// The device's saved settings, freshly read (this isolate outlives one tap),
/// with the language this device last used in effect: there is no app here to
/// hold it.
Future<StorageService> _loadStorage() async {
  final SharedPreferences stored = await SharedPreferences.getInstance();
  await stored.reload();
  final StorageService storage = StorageService(stored);
  AppTranslations.use(AppLanguage.fromStored(storage.readLanguage()));
  return storage;
}

Future<void> _reschedule(Reminder reminder, String owner) async {
  final StorageService storage = await _loadStorage();
  final NotificationPreferences prefs = NotificationCoordinator.readPreferences(
    storage,
  );
  final String payload = NotificationTarget.withOwner(
    ReminderNotificationPlanner.payloadFor(reminder),
    owner,
  );
  final LocalNotificationService local = LocalNotificationService();
  await local.refreshTimezone();
  await local.replaceSchedule(
    NotificationCoordinator.planFor(
      <Reminder>[reminder],
      DateTime.now(),
      prefs,
      owner,
    ),
    keep: const <int>{},
    sound: prefs.sound,
    vibration: prefs.vibration,
    owner: owner,
    // Only this reminder's entry; every other one stays as the app left it.
    owns: (String? scheduled) => scheduled == payload,
  );
}
