import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String v) => Decimal.parse(v);

Transaction tx(
  String id,
  TransactionType type,
  String amount, {
  String account = 'a1',
  DateTime? date,
  DateTime? deletedAt,
}) => Transaction(
  id: id,
  userId: 'u',
  accountId: account,
  type: type,
  amount: d(amount),
  transactionDate: date ?? DateTime(2026, 10, 7, 12),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  deletedAt: deletedAt,
);

Account account(String id, String opening) => Account(
  id: id,
  userId: 'u',
  name: id,
  type: AccountType.cash,
  openingBalance: d(opening),
  isActive: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Contact contact(String id, String opening, String type) => Contact(
  id: id,
  userId: 'u',
  name: id,
  openingBalance: d(opening),
  openingBalanceType: type,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ContactTransaction entry(
  String contactId,
  ContactTransactionType type,
  String amount,
) => ContactTransaction(
  id: '$contactId-$type-$amount',
  userId: 'u',
  contactId: contactId,
  type: type,
  amount: d(amount),
  transactionDate: DateTime(2026, 10, 7),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('account balances use the opening balance and skip deleted rows', () {
    final Map<String, Decimal> balances =
        FinanceSummaryCalculator.accountBalances(
          <Account>[account('a1', '1000'), account('a2', '50')],
          <Transaction>[
            tx('1', TransactionType.income, '500.50'),
            tx('2', TransactionType.expense, '200'),
            tx('3', TransactionType.expense, '999', deletedAt: DateTime(2026)),
            tx('4', TransactionType.expense, '10', account: 'a2'),
          ],
        );
    expect(balances['a1'], d('1300.5'));
    expect(balances['a2'], d('40'));
    expect(FinanceSummaryCalculator.sum(balances.values), d('1340.5'));
  });

  test('period summary counts income and expense inside the range only', () {
    final PeriodSummary month = FinanceSummaryCalculator.period(
      <Transaction>[
        tx('1', TransactionType.income, '100'),
        tx('2', TransactionType.expense, '30'),
        tx('3', TransactionType.transfer_out, '500'),
        tx('4', TransactionType.income, '9', date: DateTime(2026, 9, 30)),
        tx('5', TransactionType.income, '7', date: DateTime(2026, 11)),
      ],
      DateTime(2026, 10),
      DateTime(2026, 11),
    );
    expect(month.income, d('100'));
    expect(month.expense, d('30'));
    expect(month.net, d('70'));
  });

  test('khata totals split receivable and payable per contact', () {
    final KhataSummary summary = FinanceSummaryCalculator.khata(
      <Contact>[
        contact('asha', '100', 'receivable'),
        contact('ravi', '40', 'payable'),
      ],
      <ContactTransaction>[
        entry('asha', ContactTransactionType.credit, '50'),
        entry('ravi', ContactTransactionType.paymentMade, '100'),
      ],
    );
    expect(summary.receivable, d('210'));
    expect(summary.payable, Decimal.zero);
  });
}
