import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/khata_due_reminders.dart';
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
          ? 'Collect payment'.tr
          : (owedByUser ? 'Pay dues'.tr : 'Khata follow-up'.tr),
    );
  }

  final Reminder? existing;
  final ReminderType type;
  final String? contactId;
  final String? transactionId;
  final Decimal? amount;
  final String? title;
}

/// What Mark as paid did on a loan reminder: wrote the due instalment,
/// completed the reminder because nothing was due, or failed (the message is
/// in [ReminderController.action]).
enum LoanPaidOutcome { recorded, completed, failed }

/// Reminders: list, create, edit, complete, snooze, enable/disable, delete.
/// Every load also makes the device's scheduled notifications match the list.
class ReminderController extends GetxController {
  ReminderController(
    this._repository,
    this._contactRepository,
    this._notifications,
    this._notifier, {
    LoanRepository? loanRepository,
  }) : _loans = loanRepository;

  final ReminderRepository _repository;
  final ContactRepository _contactRepository;
  final NotificationCoordinator _notifications;
  final DataChangeNotifier _notifier;
  final LoanRepository? _loans;

  static const Uuid _uuid = Uuid();

  final RxList<Reminder> reminders = <Reminder>[].obs;
  final RxList<Contact> contacts = <Contact>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();
  final SubmitState action = SubmitState();

  // GetX does not dispose workers, and the notifier outlives this
  // controller, so without this a closed controller keeps reloading.
  late final Worker _changes;

  @override
  void onClose() {
    _changes.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    load();
    _changes = ever<int>(_notifier.version, (_) => load(silent: true));
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
      if (overdue.isNotEmpty) ReminderSection('Overdue'.tr, overdue),
      if (upcoming.isNotEmpty) ReminderSection('Upcoming'.tr, upcoming),
      if (completed.isNotEmpty) ReminderSection('Completed'.tr, completed),
    ];
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final (List<Reminder> loaded, List<Contact> loadedContacts) =
          await _loadApplyingKhataDue();
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

  Future<void> _khataTail = Future<void>.value();

  /// Reminders and contacts, after khata due dates were applied. One run at a
  /// time, each on fresh data, so an older read never saves balances over the
  /// newer ones the next run compares with.
  Future<(List<Reminder>, List<Contact>)> _loadApplyingKhataDue() {
    final Future<(List<Reminder>, List<Contact>)> run = _khataTail.then(
      (_) => _applyKhataDue(),
    );
    _khataTail = run.then<void>((_) {}).catchError((Object _) {});
    return run;
  }

  /// Gives khata due dates without a reminder one, and marks due reminders
  /// done once their dues are cleared (KhataDueReminders.plan). Runs before
  /// the schedule is synced, so a cleared reminder never fires. Backfill waits
  /// for the first pull (ReminderRepository.hasPulled). Its writes do not
  /// announce a change: that would start another load.
  Future<(List<Reminder>, List<Contact>)> _applyKhataDue() async {
    final (
      List<Reminder> live,
      List<Contact> contacts,
      List<ContactTransaction> entries,
      Map<String, int> previous,
      bool pulled,
    ) = await wait5(
      _repository.getAll(),
      _contactRepository.getContacts(),
      _contactRepository.getAllContactTransactions(),
      _repository.readKhataBalances(),
      _repository.hasPulled(),
    );
    final ({
      List<Reminder> create,
      List<Reminder> complete,
      Map<String, int> balances,
    })
    plan = KhataDueReminders.plan(
      contacts: contacts,
      entries: entries,
      reminders: live,
      previous: previous,
      now: DateTime.now(),
      titleOf: (String title) => title.tr,
    );
    final List<Reminder> create = pulled ? plan.create : const <Reminder>[];
    for (final Reminder r in create) {
      await _repository.create(r, onlyIfAbsent: true);
    }
    for (final Reminder r in plan.complete) {
      await _repository.update(r);
    }
    await _repository.saveKhataBalances(plan.balances);
    final bool changed = create.isNotEmpty || plan.complete.isNotEmpty;
    return (changed ? await _repository.getAll() : live, contacts);
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

  /// Mark as paid on a loan reminder: records the instalment that is due (the
  /// suggested split, from the loan's account) and announces the change, which
  /// reloads this list with the reminder moved. When nothing is due the
  /// reminder is completed like any other.
  Future<LoanPaidOutcome> markLoanPaid(Reminder reminder) async {
    LoanPaidOutcome outcome = LoanPaidOutcome.failed;
    await action.run(() async {
      final String? loanId = reminder.loanId;
      final LoanPayment? paid = loanId == null
          ? null
          : await _loans?.recordDuePayment(loanId);
      if (paid != null) {
        _notifier.markChanged();
        outcome = LoanPaidOutcome.recorded;
        return;
      }
      await _repository.update(
        ReminderCalculator.complete(reminder, DateTime.now()),
      );
      await load(silent: true);
      outcome = LoanPaidOutcome.completed;
    });
    return outcome;
  }

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
