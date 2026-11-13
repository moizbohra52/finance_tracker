import 'package:decimal/decimal.dart';
import 'package:finance_tracker/data/models/loan.dart';
import 'package:finance_tracker/data/models/reminder.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.parse('2026-11-11T12:00:00Z');

  Decimal d(String v) => Decimal.parse(v);

  Loan emiLoan() => Loan(
    id: 'l1',
    userId: 'u1',
    direction: LoanDirection.taken,
    method: LoanMethod.emi,
    name: 'HDFC Home Loan',
    contactId: 'c1',
    accountId: 'a1',
    principal: d('500000'),
    annualRate: d('9'),
    tenureMonths: 60,
    emiAmount: d('10379.18'),
    startDate: DateTime(2026, 1, 31),
    firstDueDate: DateTime(2026, 2, 28),
    movedMoney: true,
    closedAt: DateTime.parse('2026-11-01T18:30:00Z'),
    note: 'home',
    createdAt: now,
    updatedAt: now,
  );

  Loan monthlyLoan() => Loan(
    id: 'l2',
    userId: 'u1',
    direction: LoanDirection.given,
    method: LoanMethod.monthlyInterest,
    name: 'Ravi',
    accountId: 'a1',
    principal: d('10000'),
    annualRate: d('24'),
    startDate: DateTime(2026, 1, 1),
    movedMoney: false,
    createdAt: now,
    updatedAt: now,
  );

  group('LoanModel', () {
    test('round trips an EMI loan with every field', () {
      final Loan loan = emiLoan();
      final Map<String, dynamic> json = LoanModel.toJson(loan);

      expect(json.containsKey('created_at'), isFalse);
      expect(json.containsKey('updated_at'), isFalse);
      expect(json['direction'], 'taken');
      expect(json['method'], 'emi');
      expect(json['principal'], '500000');
      expect(json['annual_rate'], '9');
      expect(json['emi_amount'], '10379.18');
      expect(json['tenure_months'], 60);
      expect(json['start_date'], '2026-01-31');
      expect(json['first_due_date'], '2026-02-28');
      expect(json['closed_at'], '2026-11-01T18:30:00.000Z');
      expect(json['moved_money'], true);

      final Loan back = LoanModel.fromJson(<String, dynamic>{
        ...json,
        'created_at': '2026-11-11T12:00:00Z',
        'updated_at': '2026-11-11T12:00:00Z',
      });
      expect(back.id, 'l1');
      expect(back.userId, 'u1');
      expect(back.direction, LoanDirection.taken);
      expect(back.method, LoanMethod.emi);
      expect(back.name, 'HDFC Home Loan');
      expect(back.contactId, 'c1');
      expect(back.accountId, 'a1');
      expect(back.principal, d('500000'));
      expect(back.annualRate, d('9'));
      expect(back.tenureMonths, 60);
      expect(back.emiAmount, d('10379.18'));
      expect(back.startDate, DateTime(2026, 1, 31));
      expect(back.firstDueDate, DateTime(2026, 2, 28));
      expect(back.movedMoney, isTrue);
      expect(back.closedAt, DateTime.parse('2026-11-01T18:30:00Z').toLocal());
      expect(back.closedAt!.isUtc, isFalse);
      expect(back.note, 'home');
      expect(back.createdAt, now);
      expect(back.deletedAt, isNull);
    });

    test('round trips a monthly loan with the EMI fields null', () {
      final Map<String, dynamic> json = LoanModel.toJson(monthlyLoan());
      expect(json['tenure_months'], isNull);
      expect(json['emi_amount'], isNull);
      expect(json['first_due_date'], isNull);
      expect(json['closed_at'], isNull);
      expect(json['contact_id'], isNull);
      expect(json['moved_money'], false);

      final Loan back = LoanModel.fromJson(json);
      expect(back.method, LoanMethod.monthlyInterest);
      expect(back.direction, LoanDirection.given);
      expect(back.tenureMonths, isNull);
      expect(back.emiAmount, isNull);
      expect(back.firstDueDate, isNull);
      expect(back.closedAt, isNull);
      expect(back.movedMoney, isFalse);
      expect(back.startDate, DateTime(2026, 1, 1));
    });

    test('reads amounts as numbers or strings and moved_money as 0 or 1', () {
      final Map<String, dynamic> json = LoanModel.toJson(emiLoan());
      final Loan fromNums = LoanModel.fromJson(<String, dynamic>{
        ...json,
        'principal': 500000,
        'annual_rate': 9.5,
        'emi_amount': 10379.18,
        'moved_money': 1,
      });
      expect(fromNums.principal, d('500000'));
      expect(fromNums.annualRate, d('9.5'));
      expect(fromNums.emiAmount, d('10379.18'));
      expect(fromNums.movedMoney, isTrue);

      final Loan fromZero = LoanModel.fromJson(<String, dynamic>{
        ...json,
        'moved_money': 0,
      });
      expect(fromZero.movedMoney, isFalse);
    });

    test('reads a server date with a time part', () {
      final Loan back = LoanModel.fromJson(<String, dynamic>{
        ...LoanModel.toJson(emiLoan()),
        'start_date': '2026-03-05T00:00:00',
      });
      expect(back.startDate, DateTime(2026, 3, 5));
    });
  });

  group('LoanPaymentModel', () {
    final LoanPayment payment = LoanPayment(
      id: 'p1',
      userId: 'u1',
      loanId: 'l1',
      accountId: 'a1',
      kind: LoanPaymentKind.extra,
      paidAt: DateTime.parse('2026-11-05T09:30:00Z'),
      amount: d('10379.18'),
      principalPart: d('6629.18'),
      interestPart: d('3750'),
      note: 'prepay',
      createdAt: now,
      updatedAt: now,
    );

    test('round trips and writes no timestamps', () {
      final Map<String, dynamic> json = LoanPaymentModel.toJson(payment);
      expect(json.containsKey('created_at'), isFalse);
      expect(json['kind'], 'extra');
      expect(json['paid_at'], '2026-11-05T09:30:00.000Z');
      expect(json['amount'], '10379.18');
      expect(json['principal_part'], '6629.18');
      expect(json['interest_part'], '3750');

      final LoanPayment back = LoanPaymentModel.fromJson(json);
      expect(back.id, 'p1');
      expect(back.loanId, 'l1');
      expect(back.accountId, 'a1');
      expect(back.kind, LoanPaymentKind.extra);
      expect(back.paidAt, DateTime.parse('2026-11-05T09:30:00Z').toLocal());
      expect(back.paidAt.isUtc, isFalse);
      expect(back.amount, d('10379.18'));
      expect(back.principalPart, d('6629.18'));
      expect(back.interestPart, d('3750'));
      expect(back.note, 'prepay');
    });

    test('reads amounts given as numbers', () {
      final LoanPayment back = LoanPaymentModel.fromJson(<String, dynamic>{
        ...LoanPaymentModel.toJson(payment),
        'amount': 100,
        'principal_part': 60.5,
        'interest_part': 39.5,
      });
      expect(back.amount, d('100'));
      expect(back.principalPart, d('60.5'));
      expect(back.interestPart, d('39.5'));
    });
  });

  group('loan_id on transactions and reminders', () {
    Transaction transaction({String? loanId}) => Transaction(
      id: 't1',
      userId: 'u1',
      accountId: 'a1',
      type: TransactionType.payment_made,
      amount: d('100'),
      transactionDate: now,
      loanId: loanId,
      createdAt: now,
      updatedAt: now,
    );

    Reminder reminder({String? loanId, ReminderType? type}) => Reminder(
      id: 'r1',
      userId: 'u1',
      type: type ?? ReminderType.custom,
      title: 'EMI',
      description: null,
      amount: null,
      contactId: null,
      transactionId: null,
      loanId: loanId,
      remindAt: now,
      repeat: ReminderRepeat.none,
      isCompleted: false,
      notificationEnabled: true,
      snoozedUntil: null,
      createdAt: now,
      updatedAt: now,
    );

    test('a transaction round trips loan_id and is loan derived', () {
      final Transaction tx = transaction(loanId: 'l1');
      expect(tx.isLoanDerived, isTrue);
      expect(tx.toJson()['loan_id'], 'l1');
      expect(Transaction.fromJson(tx.toJson()).loanId, 'l1');
      expect(tx.copyWith(note: 'x').loanId, 'l1');

      final Map<String, dynamic> modelJson = TransactionModel.fromEntity(
        tx,
      ).toJson();
      expect(modelJson['loan_id'], 'l1');
      expect(TransactionModel.fromJson(modelJson).toEntity().loanId, 'l1');
    });

    test('a transaction without a loan has no loan_id key', () {
      final Transaction tx = transaction();
      expect(tx.isLoanDerived, isFalse);
      expect(tx.toJson().containsKey('loan_id'), isFalse);
      expect(
        TransactionModel.fromEntity(tx).toJson().containsKey('loan_id'),
        isFalse,
      );
    });

    test('a reminder round trips loan_id and has no key without one', () {
      final Reminder withLoan = reminder(loanId: 'l1', type: ReminderType.loan);
      final Map<String, dynamic> json = ReminderModel.toJson(withLoan);
      expect(json['loan_id'], 'l1');
      expect(json['reminder_type'], 'loan');
      final Reminder back = ReminderModel.fromJson(<String, dynamic>{
        ...json,
        'created_at': '2026-11-11T12:00:00Z',
        'updated_at': '2026-11-11T12:00:00Z',
      });
      expect(back.loanId, 'l1');
      expect(back.type, ReminderType.loan);
      expect(withLoan.copyWith(title: 'x').loanId, 'l1');

      expect(ReminderModel.toJson(reminder()).containsKey('loan_id'), isFalse);
    });

    test('ReminderType.fromName reads loan', () {
      expect(ReminderType.fromName('loan'), ReminderType.loan);
      expect(ReminderType.loan.label, 'Loan');
    });
  });
}
