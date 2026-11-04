import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/khata_due_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime now = DateTime(2026, 11, 4, 12);
final DateTime earlier = DateTime(2026, 11, 1);

Contact contact({String opening = '0'}) => Contact(
  id: 'c',
  userId: 'u',
  name: 'Amit',
  openingBalance: Decimal.parse(opening),
  openingBalanceType: 'receivable',
  createdAt: earlier,
  updatedAt: earlier,
);

ContactTransaction entry(
  String id,
  ContactTransactionType type,
  String amount, {
  DateTime? due,
}) => ContactTransaction(
  id: id,
  userId: 'u',
  contactId: 'c',
  type: type,
  amount: Decimal.parse(amount),
  transactionDate: earlier,
  dueDate: due,
  createdAt: earlier,
  updatedAt: earlier,
);

typedef Plan = ({
  List<Reminder> create,
  List<Reminder> complete,
  Map<String, int> balances,
});

Plan plan(
  List<ContactTransaction> entries, {
  List<Reminder> reminders = const <Reminder>[],
  Map<String, int> previous = const <String, int>{},
  Contact? owner,
}) => KhataDueReminders.plan(
  contacts: <Contact>[owner ?? contact()],
  entries: entries,
  reminders: reminders,
  previous: previous,
  now: now,
  titleOf: (String t) => t,
);

void main() {
  final ContactTransaction lent = entry(
    'lent',
    ContactTransactionType.credit,
    '500',
    due: DateTime(2026, 11, 20),
  );
  final ContactTransaction repaid = entry(
    'repaid',
    ContactTransactionType.paymentReceived,
    '500',
  );

  group('backfill', () {
    test('a due date without a reminder gets one at 09:00', () {
      final Reminder r = plan(<ContactTransaction>[lent]).create.single;
      expect(r.id, KhataDueReminders.id('lent'));
      expect(r.type, ReminderType.receivable);
      expect(r.title, 'Collect payment');
      expect(r.remindAt, DateTime(2026, 11, 20, 9));
      expect(r.isCompleted, isFalse);
    });

    test('today is backfilled, a past due date is not', () {
      final ContactTransaction today = entry(
        'today',
        ContactTransactionType.debit,
        '100',
        due: DateTime(2026, 11, 4),
      );
      final ContactTransaction past = entry(
        'past',
        ContactTransactionType.credit,
        '100',
        due: DateTime(2026, 11, 3),
      );
      final List<Reminder> created = plan(<ContactTransaction>[
        today,
        past,
      ]).create;
      expect(created.map((Reminder r) => r.id), <String>[
        KhataDueReminders.id('today'),
      ]);
      expect(created.single.type, ReminderType.payable);
    });

    test('dues already cleared are backfilled as done', () {
      expect(
        plan(<ContactTransaction>[lent, repaid]).create.single.isCompleted,
        isTrue,
      );
    });
  });

  group('completing', () {
    final Reminder open = KhataDueReminders.build(
      lent,
      title: 'Collect payment',
      now: earlier,
    );
    final Map<String, int> owed = <String, int>{'c': 1};
    final Map<String, int> settled = <String, int>{'c': 0};

    test('a repayment that clears the dues completes the reminder', () {
      final Plan p = plan(
        <ContactTransaction>[lent, repaid],
        reminders: <Reminder>[open],
        previous: owed,
      );
      expect(p.create, isEmpty);
      expect(p.complete.single.id, open.id);
      expect(p.complete.single.isCompleted, isTrue);
      expect(p.balances, settled);
    });

    test('a part payment leaves it open', () {
      expect(
        plan(
          <ContactTransaction>[
            lent,
            entry('part', ContactTransactionType.paymentReceived, '200'),
          ],
          reminders: <Reminder>[open],
          previous: owed,
        ).complete,
        isEmpty,
      );
    });

    test('deleting another entry that clears the dues completes it', () {
      // Before: lent 500 + 300 extra - 500 paid = 300 owed. The extra entry
      // is deleted (no longer loaded), leaving 0.
      expect(
        plan(
          <ContactTransaction>[lent, repaid],
          reminders: <Reminder>[open],
          previous: owed,
        ).complete,
        hasLength(1),
      );
    });

    test('an opening balance edit that clears the dues completes it', () {
      final Contact advance = Contact(
        id: 'c',
        userId: 'u',
        name: 'Amit',
        openingBalance: Decimal.parse('500'),
        openingBalanceType: 'payable',
        createdAt: earlier,
        updatedAt: now,
      );
      expect(
        plan(
          <ContactTransaction>[lent],
          reminders: <Reminder>[open],
          previous: owed,
          owner: advance,
        ).complete,
        hasLength(1),
      );
    });

    test('with the dues still cleared, a reopened reminder stays open '
        '(a name or photo edit moves nothing)', () {
      final Contact renamed = contact();
      expect(
        plan(
          <ContactTransaction>[lent, repaid],
          reminders: <Reminder>[open],
          previous: settled,
          owner: renamed,
        ).complete,
        isEmpty,
      );
    });

    test('a contact not seen before is only recorded', () {
      final Plan p = plan(
        <ContactTransaction>[lent, repaid],
        reminders: <Reminder>[open],
      );
      expect(p.complete, isEmpty);
      expect(p.balances, settled);
    });

    test('a payable completes once the user owes nothing', () {
      final ContactTransaction borrowed = entry(
        'borrowed',
        ContactTransactionType.debit,
        '300',
        due: DateTime(2026, 11, 20),
      );
      final Reminder payable = KhataDueReminders.build(
        borrowed,
        title: 'Pay dues',
        now: earlier,
      );
      expect(
        plan(
          <ContactTransaction>[
            borrowed,
            entry('back', ContactTransactionType.paymentMade, '300'),
          ],
          reminders: <Reminder>[payable],
          previous: <String, int>{'c': -1},
        ).complete.single.id,
        payable.id,
      );
    });
  });
}
