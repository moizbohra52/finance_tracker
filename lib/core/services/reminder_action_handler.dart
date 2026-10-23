import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:ui';

import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/core/services/local_notification_service.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/translations/app_translations.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:finance_tracker/domain/services/reminder_notification_planner.dart';
import 'package:finance_tracker/features/notifications/notification_target.dart';
import 'package:finance_tracker/routes/app_routes.dart';
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

/// Mark done / Snooze tapped on a reminder notification. The plugin runs this
/// in a background isolate, whether or not the app is open, so no app service
/// exists here: the change goes through the reminder's own account database
/// and sync queue, exactly as the app writes it, and only that reminder's
/// device notification is rescheduled.
@pragma('vm:entry-point')
Future<void> reminderActionInBackground(NotificationResponse response) async {
  final ReminderAction? action = ReminderAction.values
      .asNameMap()[response.actionId];
  final String? owner = NotificationTarget.ownerOf(response.payload);
  final NotificationTarget? target = NotificationTarget.fromPayload(
    response.payload,
  );
  if (action == null ||
      owner == null ||
      target == null ||
      target.route != AppRoutes.reminderDetail) {
    return;
  }
  try {
    final Reminder? changed = await _save(action, owner, target.argument!);
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
    final ReminderRepository repository = ReminderRepository(
      client,
      database: AppDatabase(database: db),
    );
    final Reminder? reminder = (await repository.getAll())
        .where((Reminder r) => r.id == reminderId)
        .firstOrNull;
    if (reminder == null || reminder.isCompleted) return null;
    final Reminder changed = ReminderCalculator.applyAction(
      reminder,
      action,
      DateTime.now(),
    );
    await repository.update(changed);
    return changed;
  } finally {
    await db.close();
    await client.dispose();
  }
}

Future<void> _reschedule(Reminder reminder, String owner) async {
  final SharedPreferences stored = await SharedPreferences.getInstance();
  // This isolate outlives one tap; the settings may have changed since.
  await stored.reload();
  final StorageService storage = StorageService(stored);
  final NotificationPreferences prefs = NotificationCoordinator.readPreferences(
    storage,
  );
  // No app here to hold the language, so the text is made in the one this
  // device last used.
  AppTranslations.use(AppLanguage.fromStored(storage.readLanguage()));
  final String payload = NotificationTarget.withOwner(
    ReminderNotificationPlanner.payloadFor(reminder.id),
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
