import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/khata_due_reminders.dart';
import 'package:finance_tracker/features/contacts/controller/contact_detail_controller.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';

void main() {
  late FakeFinance finance;
  late ContactFormController controller;
  const String id = 'entry-due';
  final String reminderId = KhataDueReminders.id(id);

  setUp(() {
    Get.testMode = true;
    finance = FakeFinance();
    controller = ContactFormController(
      finance.repositories.contacts,
      finance.repositories.transactions,
      finance.repositories.accounts,
      finance.repositories.categories,
      DataChangeNotifier(),
      reminderRepository: finance.repositories.reminders,
    );
  });

  tearDown(Get.reset);

  Future<void> save({
    ContactTransaction? existing,
    ContactTransactionType type = ContactTransactionType.credit,
    DateTime? dueDate,
    String? note,
  }) async {
    expect(
      await controller.saveEntry(
        id: id,
        existing: existing,
        contactId: 'c-amit',
        type: type,
        amount: Decimal.parse('500'),
        date: DateTime(2026, 11, 1),
        dueDate: dueDate,
        note: note,
      ),
      isTrue,
    );
  }

  ContactTransaction entry() => finance.contactTransactions.singleWhere(
    (ContactTransaction e) => e.id == id,
  );

  Reminder? reminder() =>
      finance.reminders.firstWhereOrNull((Reminder r) => r.id == reminderId);

  test('a due date creates, keeps, moves and removes one reminder', () async {
    await save(dueDate: DateTime(2026, 11, 20));
    final Reminder created = reminder()!;
    expect(created.type, ReminderType.receivable);
    expect(created.contactId, 'c-amit');
    expect(created.amount, Decimal.parse('500'));
    expect(created.remindAt, DateTime(2026, 11, 20, 9));
    expect(created.title, isNot(contains('Amit')));

    // Marked done, then only the note changes: it stays done.
    finance.reminders[0] = created.copyWith(isCompleted: true);
    await save(existing: entry(), dueDate: DateTime(2026, 11, 20), note: 'x');
    expect(reminder()!.isCompleted, isTrue);

    // A new due date makes it active again on that day.
    await save(existing: entry(), dueDate: DateTime(2026, 12, 5), note: 'x');
    expect(reminder()!.isCompleted, isFalse);
    expect(reminder()!.remindAt, DateTime(2026, 12, 5, 9));
    expect(finance.reminders, hasLength(1));

    await save(existing: entry());
    expect(reminder(), isNull);
  });

  test(
    'borrowing is a payable reminder; deleting the entry removes it',
    () async {
      await save(
        type: ContactTransactionType.debit,
        dueDate: DateTime(2026, 11, 20),
      );
      expect(reminder()!.type, ReminderType.payable);

      final ContactDetailController detail = ContactDetailController(
        finance.repositories.contacts,
        finance.repositories.transactions,
        DataChangeNotifier(),
        'c-amit',
        reminderRepository: finance.repositories.reminders,
      );
      finance.contacts.add(
        Contact(
          id: 'c-amit',
          userId: 'u',
          name: 'Amit',
          openingBalance: Decimal.zero,
          openingBalanceType: 'receivable',
          createdAt: DateTime(2026, 10),
          updatedAt: DateTime(2026, 10),
        ),
      );
      await detail.load();
      expect(await detail.deleteEntry(id), isTrue);
      expect(reminder(), isNull);
    },
  );

  test('an entry without a due date has no reminder', () async {
    await save();
    expect(finance.reminders, isEmpty);
  });
}
