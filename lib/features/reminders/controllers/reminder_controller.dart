import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// A titled group of reminders on the list screen.
class ReminderSection {
  const ReminderSection(this.title, this.reminders);

  final String title;
  final List<Reminder> reminders;
}

/// Opens the reminder form: to create (optionally prefilled from a contact or
/// transaction) or, with [existing], to edit.
class ReminderFormArgs {
  const ReminderFormArgs({
    this.existing,
    this.type = ReminderType.custom,
    this.contactId,
    this.transactionId,
    this.amount,
    this.title,
  });

  /// A reminder about a khata contact: a receivable when they owe the user
  /// (positive [balance]), a payable when the user owes them, plain khata when
  /// settled. The amount is the outstanding balance. The default title has no
  /// name or figure in it, because a title is shown in the notification.
  factory ReminderFormArgs.forContact({
    required String contactId,
    required Decimal balance,
  }) {
    final bool owedToUser = balance > Decimal.zero;
    final bool owedByUser = balance < Decimal.zero;
    return ReminderFormArgs(
      type: owedToUser
          ? ReminderType.receivable
          : (owedByUser ? ReminderType.payable : ReminderType.khata),
      contactId: contactId,
      amount: balance == Decimal.zero ? null : balance.abs(),
      title: owedToUser
          ? 'Collect payment'
          : (owedByUser ? 'Pay dues' : 'Khata follow-up'),
    );
  }

  final Reminder? existing;
  final ReminderType type;
  final String? contactId;
  final String? transactionId;
  final Decimal? amount;
  final String? title;
}

/// Reminders: list, create, edit, complete, snooze, enable/disable, delete.
/// Every load also makes the device's scheduled notifications match the list.
class ReminderController extends GetxController {
  ReminderController(
    this._repository,
    this._contactRepository,
    this._notifications,
    this._notifier,
  );

  final ReminderRepository _repository;
  final ContactRepository _contactRepository;
  final NotificationCoordinator _notifications;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final RxList<Reminder> reminders = <Reminder>[].obs;
  final RxList<Contact> contacts = <Contact>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();
  final SubmitState action = SubmitState();

  @override
  void onInit() {
    super.onInit();
    load();
    ever<int>(_notifier.version, (_) => load(silent: true));
  }

  Reminder? byId(String id) {
    for (final Reminder r in reminders) {
      if (r.id == id) return r;
    }
    return null;
  }

  String? contactName(String? id) {
    if (id == null) return null;
    for (final Contact c in contacts) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  /// Overdue first (oldest first), then what is coming (soonest first), then
  /// completed (latest first). Empty groups are left out.
  List<ReminderSection> sections([DateTime? at]) {
    final DateTime now = at ?? DateTime.now();
    final List<Reminder> overdue = <Reminder>[];
    final List<Reminder> upcoming = <Reminder>[];
    final List<Reminder> completed = <Reminder>[];
    for (final Reminder r in reminders) {
      switch (ReminderCalculator.status(r, now)) {
        case ReminderStatus.overdue:
          overdue.add(r);
        case ReminderStatus.upcoming || ReminderStatus.snoozed:
          upcoming.add(r);
        case ReminderStatus.completed:
          completed.add(r);
      }
    }
    int byDue(Reminder a, Reminder b) => a.remindAt.compareTo(b.remindAt);
    overdue.sort(byDue);
    upcoming.sort(byDue);
    completed.sort((Reminder a, Reminder b) => byDue(b, a));
    return <ReminderSection>[
      if (overdue.isNotEmpty) ReminderSection('Overdue', overdue),
      if (upcoming.isNotEmpty) ReminderSection('Upcoming', upcoming),
      if (completed.isNotEmpty) ReminderSection('Completed', completed),
    ];
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final (List<Reminder> loaded, List<Contact> loadedContacts) = await wait2(
        _repository.getAll(),
        _contactRepository.getContacts(),
      );
      reminders.assignAll(loaded);
      contacts.assignAll(loadedContacts);
      await _notifications.syncReminders(loaded);
      await _notifications.raiseDueReminders(loaded);
    } on AppException catch (failure) {
      if (!silent || reminders.isEmpty) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// [id] is generated once per form so a retried save upserts one row.
  Future<bool> saveReminder({
    required String id,
    Reminder? existing,
    required ReminderType type,
    required String title,
    required String? description,
    required Decimal? amount,
    required String? contactId,
    required String? transactionId,
    required DateTime remindAt,
    required ReminderRepeat repeat,
    required bool notificationEnabled,
  }) async {
    final bool saved = await save.run(() async {
      final DateTime now = DateTime.now();
      // Moving the schedule starts the reminder afresh: it is active again and
      // any snooze no longer applies.
      final bool rescheduled =
          existing != null &&
          (existing.remindAt != remindAt || existing.repeat != repeat);
      final Reminder reminder = Reminder(
        id: id,
        userId: existing?.userId ?? '',
        type: type,
        title: title,
        description: description,
        amount: type.hasAmount ? amount : null,
        contactId: type.involvesContact ? contactId : null,
        transactionId: transactionId,
        remindAt: remindAt,
        repeat: repeat,
        isCompleted: rescheduled ? false : (existing?.isCompleted ?? false),
        notificationEnabled: notificationEnabled,
        snoozedUntil: rescheduled ? null : existing?.snoozedUntil,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      if (existing == null) {
        await _repository.create(reminder);
      } else {
        await _repository.update(reminder);
      }
      await load(silent: true);
    });
    // Saving a reminder is the natural moment to ask for permission; the
    // coordinator asks at most once and never after a refusal.
    if (saved &&
        notificationEnabled &&
        _notifications.preferences.value.enabled &&
        _notifications.permission.value.canPrompt) {
      await _notifications.requestPermission();
    }
    return saved;
  }

  Future<bool> complete(Reminder reminder) => _update(
    reminder,
    (Reminder r) => ReminderCalculator.complete(r, DateTime.now()),
  );

  Future<bool> reopen(Reminder reminder) =>
      _update(reminder, ReminderCalculator.reopen);

  Future<bool> snooze(Reminder reminder, SnoozeOption option) => _update(
    reminder,
    (Reminder r) => r.copyWith(
      snoozedUntil: ReminderCalculator.snoozeUntil(option, DateTime.now()),
    ),
  );

  Future<bool> setNotificationEnabled(Reminder reminder, bool enabled) =>
      _update(
        reminder,
        (Reminder r) => r.copyWith(notificationEnabled: enabled),
      );

  Future<bool> _update(Reminder reminder, Reminder Function(Reminder) change) =>
      action.run(() async {
        await _repository.update(change(reminder));
        await load(silent: true);
      });

  Future<bool> deleteReminder(String id) => deletion.run(() async {
    await _repository.delete(id);
    await load(silent: true);
  });

  static String newId() => _uuid.v4();
}
