import 'package:decimal/decimal.dart';
import 'package:finance_tracker/data/models/contact_transaction.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.parse('2026-10-26T12:00:00Z');

  Transaction transaction({String? expenseId, String? settlementId}) =>
      Transaction(
        id: 't1',
        userId: 'u1',
        accountId: 'a1',
        categoryId: 'c1',
        contactId: null,
        type: TransactionType.expense,
        amount: Decimal.parse('300'),
        transactionDate: now,
        note: null,
        description: 'Dinner',
        paymentMethod: null,
        transferId: null,
        attachmentUrl: null,
        splitExpenseId: expenseId,
        splitSettlementId: settlementId,
        createdAt: now,
        updatedAt: now,
      );

  ContactTransaction khataEntry({String? expenseId, String? settlementId}) =>
      ContactTransaction(
        id: 'ct1',
        userId: 'u1',
        contactId: 'friend',
        type: ContactTransactionType.credit,
        amount: Decimal.parse('200'),
        transactionDate: now,
        dueDate: null,
        note: null,
        splitExpenseId: expenseId,
        splitSettlementId: settlementId,
        createdAt: now,
        updatedAt: now,
      );

  group('TransactionModel split link columns', () {
    test('round trips both ids set', () {
      final TransactionModel model = TransactionModel.fromEntity(
        transaction(expenseId: 'e1', settlementId: 's1'),
      );
      final Map<String, dynamic> json = model.toJson();
      expect(json['split_expense_id'], 'e1');
      expect(json['split_settlement_id'], 's1');
      final Transaction back = TransactionModel.fromJson(json).toEntity();
      expect(back.splitExpenseId, 'e1');
      expect(back.splitSettlementId, 's1');
    });

    test('round trips both ids null', () {
      final TransactionModel model = TransactionModel.fromEntity(transaction());
      final Transaction back = TransactionModel.fromJson(
        model.toJson(),
      ).toEntity();
      expect(back.splitExpenseId, isNull);
      expect(back.splitSettlementId, isNull);
    });

    test('copyWith keeps the ids', () {
      final Transaction original = transaction(expenseId: 'e1');
      final Transaction changed = original.copyWith(amount: Decimal.parse('5'));
      expect(changed.splitExpenseId, 'e1');
      expect(changed.splitSettlementId, isNull);
      expect(changed.amount, Decimal.parse('5'));
    });
  });

  group('ContactTransactionModel split link columns', () {
    test('round trips both ids set', () {
      final ContactTransactionModel model = ContactTransactionModel.fromEntity(
        khataEntry(expenseId: 'e1', settlementId: 's1'),
      );
      final Map<String, dynamic> json = model.toJson();
      expect(json['split_expense_id'], 'e1');
      expect(json['split_settlement_id'], 's1');
      final ContactTransaction back = ContactTransactionModel.fromJson(
        json,
      ).toEntity();
      expect(back.splitExpenseId, 'e1');
      expect(back.splitSettlementId, 's1');
    });

    test('round trips both ids null', () {
      final ContactTransactionModel model = ContactTransactionModel.fromEntity(
        khataEntry(),
      );
      final ContactTransaction back = ContactTransactionModel.fromJson(
        model.toJson(),
      ).toEntity();
      expect(back.splitExpenseId, isNull);
      expect(back.splitSettlementId, isNull);
    });
  });
}
