import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:uuid/uuid.dart';

/// The one-time reminder a khata entry's due date gets, and when the dues it
/// is about count as cleared (docs/08, "Khata due dates").
abstract final class KhataDueReminders {
  static const Uuid _uuid = Uuid();

  /// Deterministic, so saving, backfilling or deleting an entry always refers
  /// to the same reminder, on every device.
  static String id(String entryId) =>
      _uuid.v5(Namespace.url.value, 'contact-transaction-due:$entryId');

  /// 09:00 local on the due date.
  static DateTime remindAt(DateTime due) =>
      DateTime(due.year, due.month, due.day, 9);

  /// Reminder type and untranslated title for an entry of [type]. The title
  /// has no name or figure, because it is shown in the notification.
  static (ReminderType, String) kind(ContactTransactionType type) =>
      switch (type) {
        ContactTransactionType.credit => (
          ReminderType.receivable,
          'Collect payment',
        ),
        ContactTransactionType.debit => (ReminderType.payable, 'Pay dues'),
        _ => (ReminderType.khata, 'Khata follow-up'),
      };

  /// Whether the contact's [balance] (positive: they owe the user) leaves
  /// nothing for a reminder of [type]: a receivable once they owe nothing, a
  /// payable once the user owes nothing, anything else once settled.
  static bool isCleared(ReminderType type, Decimal balance) => switch (type) {
    ReminderType.receivable => balance <= Decimal.zero,
    ReminderType.payable => balance >= Decimal.zero,
    _ => balance == Decimal.zero,
  };

  /// The reminder for [entry], which must have a due date. [title] is the
  /// translated [kind] title.
  static Reminder build(
    ContactTransaction entry, {
    required String title,
    required DateTime now,
    bool isCompleted = false,
  }) => Reminder(
    id: id(entry.id),
    userId: entry.userId,
    type: kind(entry.type).$1,
    title: title,
    description: null,
    amount: entry.amount,
    contactId: entry.contactId,
    transactionId: null,
    remindAt: remindAt(entry.dueDate!),
    repeat: ReminderRepeat.none,
    isCompleted: isCompleted,
    notificationEnabled: true,
    snoozedUntil: null,
    createdAt: now,
    updatedAt: now,
  );

  /// What a reminders load writes, given the live [contacts], live [entries]
  /// and live [reminders], and each contact's balance sign at the previous
  /// load ([previous]; missing when not seen before):
  /// - [create] (only if absent, so a reminder the user deleted stays
  ///   deleted): entries due today or later that have no reminder, for
  ///   example saved before due-date reminders existed. Created done when the
  ///   dues are already cleared. Past due dates are skipped: the day to remind
  ///   on is gone.
  /// - [complete]: open due reminders whose dues went from outstanding at the
  ///   previous load to cleared now, by whatever change (a repayment, a
  ///   deleted entry, an opening balance edit, a sync). A change that does not
  ///   move the balance (a name or photo) does nothing, and a reminder the
  ///   user reopens stays open until the dues are cleared again.
  /// - [balances]: the signs to pass as [previous] next time.
  /// [titleOf] translates a [kind] title.
  static ({
    List<Reminder> create,
    List<Reminder> complete,
    Map<String, int> balances,
  })
  plan({
    required List<Contact> contacts,
    required List<ContactTransaction> entries,
    required List<Reminder> reminders,
    required Map<String, int> previous,
    required DateTime now,
    required String Function(String title) titleOf,
  }) {
    final Map<String, List<ContactTransaction>> byContact =
        <String, List<ContactTransaction>>{};
    for (final ContactTransaction e in entries) {
      (byContact[e.contactId] ??= <ContactTransaction>[]).add(e);
    }
    final Map<String, Decimal> balance = <String, Decimal>{
      for (final Contact c in contacts)
        c.id: c.getCurrentBalance(
          byContact[c.id] ?? const <ContactTransaction>[],
        ),
    };
    final Map<String, Reminder> live = <String, Reminder>{
      for (final Reminder r in reminders) r.id: r,
    };
    final DateTime today = DateTime(now.year, now.month, now.day);

    final List<Reminder> create = <Reminder>[];
    final List<Reminder> complete = <Reminder>[];
    for (final ContactTransaction e in entries) {
      final DateTime? due = e.dueDate;
      final Decimal? owed = balance[e.contactId];
      if (due == null || owed == null) continue;
      final Reminder? r = live[id(e.id)];
      if (r == null) {
        if (DateTime(due.year, due.month, due.day).isBefore(today)) continue;
        create.add(
          build(
            e,
            title: titleOf(kind(e.type).$2),
            now: now,
            isCompleted: isCleared(kind(e.type).$1, owed),
          ),
        );
        continue;
      }
      final int? before = previous[e.contactId];
      if (!r.isCompleted &&
          isCleared(r.type, owed) &&
          before != null &&
          !isCleared(r.type, Decimal.fromInt(before))) {
        complete.add(ReminderCalculator.complete(r, now));
      }
    }
    return (
      create: create,
      complete: complete,
      balances: <String, int>{
        for (final MapEntry<String, Decimal> b in balance.entries)
          b.key: b.value.sign,
      },
    );
  }
}
