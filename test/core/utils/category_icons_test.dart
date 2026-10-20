import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransactionType presentation & inflow', () {
    test('opening_balance is treated as inflow with positive balance effect', () {
      expect(TransactionType.opening_balance.isInflow, isTrue);
      expect(TransactionType.income.isInflow, isTrue);
      expect(TransactionType.transfer_in.isInflow, isTrue);
      expect(TransactionType.expense.isInflow, isFalse);
      expect(TransactionType.transfer_out.isInflow, isFalse);
    });

    test('opening_balance icon is wallet', () {
      expect(
        CategoryIcons.forType(TransactionType.opening_balance),
        Icons.account_balance_wallet_rounded,
      );
    });

    test('TransactionListItem.titleFor handles opening_balance cleanly', () {
      final Transaction t = Transaction(
        id: 'tx-1',
        userId: 'u1',
        accountId: 'acc-1',
        type: TransactionType.opening_balance,
        amount: Decimal.parse('1000'),
        transactionDate: DateTime(2026, 10, 20),
        createdAt: DateTime(2026, 10, 20),
        updatedAt: DateTime(2026, 10, 20),
      );

      final String title = TransactionListItem.titleFor(
        t,
        categoryName: null,
        nearby: const <Transaction>[],
        accountName: (_) => 'Cash',
      );

      expect(title, 'Opening balance');
    });
  });
}
