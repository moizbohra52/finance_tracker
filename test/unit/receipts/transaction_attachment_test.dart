import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';

void main() {
  test('attachment_url survives the model round trip', () {
    final Transaction entity = TransactionModel.fromJson(<String, dynamic>{
      'id': 'tx-1',
      'user_id': 'user-1',
      'account_id': 'acc-1',
      'type': 'expense',
      'amount': '120.50',
      'transaction_date': '2026-10-21T10:00:00.000Z',
      'attachment_url': 'user-1/tx-1',
      'created_at': '2026-10-21T10:00:00.000Z',
      'updated_at': '2026-10-21T10:00:00.000Z',
    }).toEntity();

    expect(entity.attachmentUrl, 'user-1/tx-1');
    expect(
      TransactionModel.fromEntity(entity).toJson()['attachment_url'],
      'user-1/tx-1',
    );
    expect(Transaction.fromJson(entity.toJson()).attachmentUrl, 'user-1/tx-1');
  });

  test('editing keeps the receipt', () async {
    final FakeFinance finance = FakeFinance()..addAccount('Cash', '0');
    final Transaction stored = finance.addTransaction(
      id: 'tx-1',
      type: TransactionType.expense,
      amount: '50',
      attachmentUrl: 'user-1/tx-1',
    );
    final TransactionController controller = TransactionController(
      finance.repositories.transactions,
      finance.repositories.accounts,
      finance.repositories.categories,
      DataChangeNotifier(),
    );

    final bool saved = await controller.saveTransaction(
      id: 'tx-1',
      existing: stored,
      type: TransactionType.expense,
      amount: Decimal.parse('99'),
      accountId: 'acc-1',
      categoryId: null,
      date: stored.transactionDate,
      note: 'changed',
    );

    expect(saved, isTrue);
    expect(finance.transactions.single.note, 'changed');
    expect(finance.transactions.single.attachmentUrl, 'user-1/tx-1');
  });
}
