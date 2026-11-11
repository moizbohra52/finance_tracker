import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/insights_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String v) => Decimal.parse(v);

int _id = 0;
Transaction tx(
  String amount,
  DateTime date, {
  TransactionType type = TransactionType.expense,
  String? category,
  DateTime? deletedAt,
}) => Transaction(
  id: 't${_id++}',
  userId: 'u',
  accountId: 'a',
  categoryId: category,
  type: type,
  amount: d(amount),
  transactionDate: date,
  createdAt: date,
  updatedAt: date,
  deletedAt: deletedAt,
);

final KhataSummary noKhata = KhataSummary.zero;

MonthInsights run(
  List<Transaction> transactions,
  DateTime now, {
  String balance = '0',
  KhataSummary? khata,
}) => InsightsCalculator.month(
  transactions: transactions,
  accountsBalance: d(balance),
  khata: khata ?? noKhata,
  now: now,
);

void main() {
  group('windows', () {
    test('this month to the end of today, last month to the same day', () {
      final ({
        DateTime currentStart,
        DateTime currentEnd,
        DateTime previousStart,
        DateTime previousEnd,
      })
      w = InsightsCalculator.windows(DateTime(2026, 11, 10, 15, 30));
      expect(w.currentStart, DateTime(2026, 11));
      expect(w.currentEnd, DateTime(2026, 11, 11));
      expect(w.previousStart, DateTime(2026, 10));
      expect(w.previousEnd, DateTime(2026, 10, 11));
    });

    test('a shorter last month ends on its last day', () {
      final ({
        DateTime currentStart,
        DateTime currentEnd,
        DateTime previousStart,
        DateTime previousEnd,
      })
      w = InsightsCalculator.windows(DateTime(2026, 3, 31));
      expect(w.previousStart, DateTime(2026, 2));
      expect(w.previousEnd, DateTime(2026, 3), reason: 'all of February');
    });

    test('January compares with December of the year before', () {
      final ({
        DateTime currentStart,
        DateTime currentEnd,
        DateTime previousStart,
        DateTime previousEnd,
      })
      w = InsightsCalculator.windows(DateTime(2026, 1, 5));
      expect(w.previousStart, DateTime(2025, 12));
      expect(w.previousEnd, DateTime(2025, 12, 6));
    });
  });

  group('spending so far', () {
    final DateTime now = DateTime(2026, 11, 10, 12);

    test('compares the same days and gives a whole percent', () {
      final MonthInsights m = run(<Transaction>[
        tx('1180', DateTime(2026, 11, 3)),
        tx('1000', DateTime(2026, 10, 4)),
        // After the 10th of last month: not part of the comparison.
        tx('5000', DateTime(2026, 10, 20)),
        // Income, a deleted expense and a transfer do not count.
        tx('900', DateTime(2026, 11, 2), type: TransactionType.income),
        tx('400', DateTime(2026, 11, 2), deletedAt: DateTime(2026, 11, 2)),
        tx('700', DateTime(2026, 11, 2), type: TransactionType.transfer_out),
      ], now);
      expect(m.spentSoFar, d('1180'));
      expect(m.spentLastMonthSoFar, d('1000'));
      expect(m.changePercent, 18);
    });

    test('less spending gives a negative percent', () {
      final MonthInsights m = run(<Transaction>[
        tx('750', DateTime(2026, 11, 1)),
        tx('1000', DateTime(2026, 10, 1)),
      ], now);
      expect(m.changePercent, -25);
    });

    test('no percent when last month had nothing by now', () {
      final MonthInsights m = run(<Transaction>[
        tx('750', DateTime(2026, 11, 1)),
      ], now);
      expect(m.spentLastMonthSoFar, Decimal.zero);
      expect(m.changePercent, isNull);
    });

    test('nothing at all', () {
      final MonthInsights m = run(const <Transaction>[], now);
      expect(m.spentSoFar, Decimal.zero);
      expect(m.changePercent, isNull);
      expect(m.topIncrease, isNull);
    });
  });

  group('biggest rise', () {
    final DateTime now = DateTime(2026, 11, 10);

    test('is the category that rose most against the same days', () {
      final MonthInsights m = run(<Transaction>[
        tx('3000', DateTime(2026, 11, 2), category: 'food'),
        tx('600', DateTime(2026, 10, 2), category: 'food'),
        tx('900', DateTime(2026, 11, 2), category: 'fuel'),
        tx('100', DateTime(2026, 10, 2), category: 'fuel'),
        // Down from last month: never the biggest rise.
        tx('100', DateTime(2026, 11, 2), category: 'rent'),
        tx('9000', DateTime(2026, 10, 2), category: 'rent'),
      ], now);
      expect(m.topIncrease?.categoryId, 'food');
      expect(m.topIncrease?.amount, d('2400'));
    });

    test('a new category counts its whole amount', () {
      final MonthInsights m = run(<Transaction>[
        tx('500', DateTime(2026, 11, 2), category: 'gifts'),
      ], now);
      expect(m.topIncrease?.categoryId, 'gifts');
      expect(m.topIncrease?.amount, d('500'));
    });

    test('none when every category is the same or lower', () {
      final MonthInsights m = run(<Transaction>[
        tx('500', DateTime(2026, 11, 2), category: 'food'),
        tx('500', DateTime(2026, 10, 2), category: 'food'),
      ], now);
      expect(m.topIncrease, isNull);
    });
  });

  test('net worth adds what others owe and takes off what the user owes', () {
    final MonthInsights m = run(
      const <Transaction>[],
      DateTime(2026, 11, 10),
      balance: '10000',
      khata: KhataSummary(receivable: d('2500'), payable: d('700')),
    );
    expect(m.netWorth, d('11800'));
  });
}
