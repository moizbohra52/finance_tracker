import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/reminder_action_handler.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/loan_ids.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/reminder_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late LoanRepository loans;
  late ReminderRepository reminders;

  setUp(() async {
    database = await AppDatabase.inMemory();
    loans = LoanRepository(database);
    reminders = ReminderRepository(
      SupabaseClient('https://dummy.supabase.co', 'dummy-anon-key'),
      database: database,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Decimal d(String v) => Decimal.parse(v);
  final DateTime made = DateTime(2027, 1, 5, 12);

  Loan emiLoan({
    String id = 'loan-1',
    String principal = '500000',
    String rate = '9',
    int months = 60,
    String emi = '10379.18',
  }) => Loan(
    id: id,
    userId: '',
    direction: LoanDirection.taken,
    method: LoanMethod.emi,
    name: 'HDFC Home Loan',
    accountId: 'acc-1',
    principal: d(principal),
    annualRate: d(rate),
    tenureMonths: months,
    emiAmount: d(emi),
    startDate: DateTime(2027, 1, 5),
    firstDueDate: DateTime(2027, 2, 5),
    movedMoney: true,
    createdAt: made,
    updatedAt: made,
  );

  Future<Reminder> loanReminder(String loanId) async =>
      (await reminders.getAll()).singleWhere(
        (Reminder r) => r.id == LoanIds.reminder(loanId),
      );

  Future<int> livePayments() async => (await database.db.query(
    'loan_payments',
    where: 'deleted_at IS NULL',
  )).length;

  Future<Reminder?> act(
    ReminderAction action,
    String reminderId,
    DateTime now,
  ) => applyReminderAction(
    reminders: reminders,
    loans: loans,
    action: action,
    reminderId: reminderId,
    now: now,
  );

  // The loan's reminder is due at 09:00 on 5 Feb 2027; the button is tapped
  // a minute later.
  final DateTime tapped = DateTime(2027, 2, 5, 9, 1);

  test('Paid on a loan reminder records the instalment and moves it', () async {
    await loans.saveLoan(emiLoan());

    final Reminder? changed = await act(
      ReminderAction.done,
      LoanIds.reminder('loan-1'),
      tapped,
    );

    expect(await livePayments(), 1);
    final Map<String, Object?> payment = (await database.db.query(
      'loan_payments',
    )).single;
    expect(payment['amount'], '10379.18');
    expect(payment['principal_part'], '6629.18');
    expect(payment['account_id'], 'acc-1');
    expect(changed, isNotNull);
    expect(changed!.id, LoanIds.reminder('loan-1'));
    expect(changed.remindAt, DateTime(2027, 3, 5, 9));
    expect(changed.isCompleted, isFalse);
    expect(await loanReminder('loan-1'), isA<Reminder>());
  });

  test('a replayed tap records nothing: the reminder already moved', () async {
    await loans.saveLoan(emiLoan());
    await act(ReminderAction.done, LoanIds.reminder('loan-1'), tapped);

    final Reminder? again = await act(
      ReminderAction.done,
      LoanIds.reminder('loan-1'),
      tapped.add(const Duration(seconds: 2)),
    );

    expect(again, isNull);
    expect(await livePayments(), 1);
    expect((await loanReminder('loan-1')).remindAt, DateTime(2027, 3, 5, 9));
  });

  test('a done reminder is left alone', () async {
    await loans.saveLoan(emiLoan());
    final Reminder due = await loanReminder('loan-1');
    await reminders.update(due.copyWith(isCompleted: true));

    final Reminder? changed = await act(ReminderAction.done, due.id, tapped);

    expect(changed, isNull);
    expect(await livePayments(), 0);
  });

  test(
    'the instalment that closes the loan hands back a silent reminder',
    () async {
      await loans.saveLoan(
        emiLoan(principal: '10000', rate: '12', months: 1, emi: '10100'),
      );

      final Reminder? changed = await act(
        ReminderAction.done,
        LoanIds.reminder('loan-1'),
        tapped,
      );

      expect(await livePayments(), 1);
      expect((await loans.getLoans()).single.loan.isClosed, isTrue);
      expect(await reminders.getAll(), isEmpty);
      expect(changed, isNotNull);
      // Nothing for the caller to schedule: its notification gets cancelled.
      expect(ReminderCalculator.nextFire(changed!, tapped), isNull);
    },
  );

  test('with nothing due, Paid completes the reminder as before', () async {
    final Loan zeroRate = Loan(
      id: 'free',
      userId: '',
      direction: LoanDirection.given,
      method: LoanMethod.monthlyInterest,
      name: 'Ravi',
      accountId: 'acc-1',
      principal: d('1000'),
      annualRate: Decimal.zero,
      startDate: DateTime(2027, 1, 5),
      movedMoney: false,
      createdAt: made,
      updatedAt: made,
    );
    await loans.saveLoan(zeroRate);
    final Reminder due = await loanReminder('free');

    final Reminder? changed = await act(
      ReminderAction.done,
      due.id,
      due.remindAt.add(const Duration(minutes: 1)),
    );

    expect(changed!.isCompleted, isTrue);
    expect((await loanReminder('free')).isCompleted, isTrue);
    expect(await livePayments(), 0);
  });

  test('Snooze on a loan reminder only snoozes it', () async {
    await loans.saveLoan(emiLoan());

    final Reminder? changed = await act(
      ReminderAction.snooze,
      LoanIds.reminder('loan-1'),
      tapped,
    );

    expect(changed!.snoozedUntil, tapped.add(const Duration(hours: 1)));
    expect(await livePayments(), 0);
    expect((await loanReminder('loan-1')).remindAt, DateTime(2027, 2, 5, 9));
  });

  test('Mark done on any other reminder still completes it', () async {
    final Reminder bill = makeReminder(remindAt: DateTime(2027, 2, 5, 9));
    await reminders.create(bill);

    final Reminder? changed = await act(ReminderAction.done, bill.id, tapped);

    expect(changed!.isCompleted, isTrue);
    expect((await reminders.getAll()).single.isCompleted, isTrue);
    expect(await livePayments(), 0);
  });

  test('a reminder that no longer exists changes nothing', () async {
    expect(await act(ReminderAction.done, 'gone', tapped), isNull);
  });
}
