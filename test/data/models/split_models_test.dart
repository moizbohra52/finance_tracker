import 'package:decimal/decimal.dart';
import 'package:finance_tracker/data/models/split.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.parse('2026-10-26T12:00:00Z');

  group('SplitGroupModel', () {
    test('round trips a group', () {
      final SplitGroup group = SplitGroup(
        id: 'g1',
        userId: 'u1',
        name: 'Goa Trip',
        createdAt: now,
        updatedAt: now,
      );
      final Map<String, dynamic> json = SplitGroupModel.toJson(group);
      expect(json.containsKey('created_at'), isFalse);
      expect(json.containsKey('updated_at'), isFalse);
      final SplitGroup back = SplitGroupModel.fromJson(json);
      expect(back.id, group.id);
      expect(back.name, group.name);
      expect(back.deletedAt, isNull);
    });
  });

  group('SplitMemberModel', () {
    test('round trips a friend and the user member', () {
      final SplitMember friend = SplitMember(
        id: 'm1',
        userId: 'u1',
        groupId: 'g1',
        contactId: 'c1',
        createdAt: now,
        updatedAt: now,
      );
      final SplitMember me = SplitMember(
        id: 'm2',
        userId: 'u1',
        groupId: 'g1',
        contactId: null,
        createdAt: now,
        updatedAt: now,
      );
      final SplitMember friendBack = SplitMemberModel.fromJson(
        SplitMemberModel.toJson(friend),
      );
      expect(friendBack.contactId, 'c1');
      final SplitMember meBack = SplitMemberModel.fromJson(
        SplitMemberModel.toJson(me),
      );
      expect(meBack.contactId, isNull);
      expect(meBack.isMe, isTrue);
    });
  });

  group('SplitExpenseModel', () {
    test('round trips an expense', () {
      final SplitExpense expense = SplitExpense(
        id: 'e1',
        userId: 'u1',
        groupId: 'g1',
        title: 'Dinner',
        totalAmount: Decimal.parse('1200.55'),
        expenseDate: now,
        splitMode: SplitMode.percent,
        categoryId: 'cat',
        accountId: 'acc',
        note: 'note',
        createdAt: now,
        updatedAt: now,
      );
      final Map<String, dynamic> json = SplitExpenseModel.toJson(expense);
      expect(json['total_amount'], '1200.55');
      expect(json['split_mode'], 'percent');
      expect(json.containsKey('created_at'), isFalse);
      final SplitExpense back = SplitExpenseModel.fromJson(json);
      expect(back.totalAmount, expense.totalAmount);
      expect(back.splitMode, SplitMode.percent);
      expect(back.expenseDate, expense.expenseDate.toLocal());
      expect(back.note, 'note');
    });

    test('accepts amounts as num or string', () {
      final Map<String, dynamic> base = SplitExpenseModel.toJson(
        SplitExpense(
          id: 'e1',
          userId: 'u1',
          groupId: 'g1',
          title: 'Dinner',
          totalAmount: Decimal.parse('1200'),
          expenseDate: now,
          splitMode: SplitMode.equal,
          categoryId: null,
          accountId: null,
          note: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(
        SplitExpenseModel.fromJson({...base, 'total_amount': 1200}).totalAmount,
        Decimal.parse('1200'),
      );
      expect(
        SplitExpenseModel.fromJson({
          ...base,
          'total_amount': '1200',
        }).totalAmount,
        Decimal.parse('1200'),
      );
    });
  });

  group('SplitPartModel', () {
    test('round trips a part with and without a share input', () {
      final SplitPart part = SplitPart(
        id: 'p1',
        userId: 'u1',
        splitExpenseId: 'e1',
        memberId: 'm1',
        paidAmount: Decimal.parse('800'),
        shareAmount: Decimal.parse('300.33'),
        shareInput: Decimal.parse('25.5'),
        createdAt: now,
        updatedAt: now,
      );
      final SplitPart back = SplitPartModel.fromJson(
        SplitPartModel.toJson(part),
      );
      expect(back.paidAmount, part.paidAmount);
      expect(back.shareAmount, part.shareAmount);
      expect(back.shareInput, Decimal.parse('25.5'));
      final SplitPart withoutInput = SplitPartModel.fromJson({
        ...SplitPartModel.toJson(part),
        'share_input': null,
      });
      expect(withoutInput.shareInput, isNull);
    });

    test('accepts paid and share amounts as num or string', () {
      final SplitPart part = SplitPart(
        id: 'p1',
        userId: 'u1',
        splitExpenseId: 'e1',
        memberId: 'm1',
        paidAmount: Decimal.parse('800'),
        shareAmount: Decimal.parse('300'),
        createdAt: now,
        updatedAt: now,
      );
      final Map<String, dynamic> json = SplitPartModel.toJson(part);
      expect(
        SplitPartModel.fromJson({
          ...json,
          'paid_amount': 800,
          'share_amount': '300',
        }).paidAmount,
        Decimal.parse('800'),
      );
    });
  });

  group('SplitSettlementModel', () {
    test('round trips a settlement', () {
      final SplitSettlement settlement = SplitSettlement(
        id: 's1',
        userId: 'u1',
        groupId: 'g1',
        fromMemberId: 'm1',
        toMemberId: 'm2',
        amount: Decimal.parse('250.75'),
        settledAt: now,
        accountId: 'acc',
        note: 'upi',
        createdAt: now,
        updatedAt: now,
      );
      final Map<String, dynamic> json = SplitSettlementModel.toJson(settlement);
      expect(json['amount'], '250.75');
      expect(json.containsKey('created_at'), isFalse);
      final SplitSettlement back = SplitSettlementModel.fromJson(json);
      expect(back.amount, settlement.amount);
      expect(back.settledAt, settlement.settledAt.toLocal());
      expect(back.accountId, 'acc');
    });
  });
}
