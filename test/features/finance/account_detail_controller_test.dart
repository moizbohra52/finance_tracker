import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/accounts/controllers/account_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';

void main() {
  test('pages through every transaction and totals the full history', () async {
    final FakeFinance f = FakeFinance()..addAccount('Cash', '1000');
    // 70 expenses of 10 and one income of 500, each on its own day.
    for (int i = 0; i < 70; i++) {
      f.addTransaction(
        id: 'e$i',
        type: TransactionType.expense,
        amount: '10',
        date: DateTime(2026, 1, 1).add(Duration(days: i)),
      );
    }
    f.addTransaction(
      id: 'income',
      type: TransactionType.income,
      amount: '500',
      date: DateTime(2025, 12, 1),
    );
    // An opening-balance row is already in the account's opening balance.
    f.addTransaction(
      id: 'opening',
      type: TransactionType.opening_balance,
      amount: '1000',
      date: DateTime(2025, 11, 1),
    );
    final DataChangeNotifier notifier = DataChangeNotifier();
    final AccountDetailController c = AccountDetailController(
      f.repositories.accounts,
      f.repositories.transactions,
      notifier,
      'acc-1',
    );

    await c.load();
    expect(c.items.length, AccountDetailController.pageSize);
    expect(c.hasMore.value, isTrue);
    // Totals cover all rows, not just the first page.
    expect(c.summary.value!.totalIncome, Decimal.fromInt(500));
    expect(c.summary.value!.totalExpense, Decimal.fromInt(700));
    expect(c.summary.value!.balance, Decimal.fromInt(800));

    await c.loadMore();
    await c.loadMore();
    expect(c.items.length, 72);
    expect(c.hasMore.value, isFalse);
    expect(c.items.map((Transaction t) => t.id).toSet().length, 72);

    // A silent reload keeps every loaded row, so the list does not jump.
    await c.load(silent: true);
    expect(c.items.length, 72);
  });
}
