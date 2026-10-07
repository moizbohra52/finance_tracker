import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/report_calculator.dart';
import 'package:finance_tracker/domain/services/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String v) => Decimal.parse(v);

Transaction tx(
  TransactionType type,
  String amount,
  DateTime date, {
  String account = 'a1',
  String? category,
  DateTime? deletedAt,
}) => Transaction(
  id: '${type.name}-$amount-${date.microsecondsSinceEpoch}-$account',
  userId: 'u',
  accountId: account,
  categoryId: category,
  type: type,
  amount: d(amount),
  transactionDate: date,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  deletedAt: deletedAt,
);

// Wednesday.
final DateTime now = DateTime(2026, 10, 7, 15, 30);

void main() {
  group('ReportPeriod', () {
    test('today covers exactly one calendar day', () {
      final ReportPeriod p = ReportPeriod.resolve(DatePreset.today, now);
      expect(p.start, DateTime(2026, 10, 7));
      expect(p.end, DateTime(2026, 10, 8));
      expect(p.contains(DateTime(2026, 10, 7, 23, 59, 59)), isTrue);
      expect(p.contains(DateTime(2026, 10, 8)), isFalse);
    });

    test('week starts on Monday', () {
      final ReportPeriod p = ReportPeriod.resolve(DatePreset.thisWeek, now);
      expect(p.start, DateTime(2026, 10, 5));
      expect(p.end, DateTime(2026, 10, 12));
      expect(p.days, 7);
    });

    test('month, last month and year boundaries', () {
      final ReportPeriod m = ReportPeriod.resolve(DatePreset.thisMonth, now);
      expect(m.start, DateTime(2026, 10));
      expect(m.end, DateTime(2026, 11));
      final ReportPeriod l = ReportPeriod.resolve(DatePreset.lastMonth, now);
      expect(l.start, DateTime(2026, 9));
      expect(l.end, DateTime(2026, 10));
      final ReportPeriod y = ReportPeriod.resolve(DatePreset.thisYear, now);
      expect(y.start, DateTime(2026));
      expect(y.end, DateTime(2027));
    });

    test('last month rolls back across a year boundary', () {
      final ReportPeriod l = ReportPeriod.resolve(
        DatePreset.lastMonth,
        DateTime(2026, 1, 15),
      );
      expect(l.start, DateTime(2025, 12));
      expect(l.end, DateTime(2026));
    });

    test(
      'custom range is inclusive of both days and tolerates swapped ends',
      () {
        final ReportPeriod p = ReportPeriod.resolve(
          DatePreset.custom,
          now,
          customStart: DateTime(2026, 10, 20),
          customEnd: DateTime(2026, 10, 10),
        );
        expect(p.start, DateTime(2026, 10, 10));
        expect(p.lastDay, DateTime(2026, 10, 20));
        expect(p.contains(DateTime(2026, 10, 20, 23)), isTrue);
        expect(p.contains(DateTime(2026, 10, 21)), isFalse);
      },
    );
  });

  group('ReportCalculator', () {
    final ReportPeriod month = ReportPeriod.resolve(DatePreset.thisMonth, now);
    final List<Transaction> data = <Transaction>[
      tx(
        TransactionType.income,
        '1000',
        DateTime(2026, 10, 1),
        category: 'sal',
      ),
      tx(
        TransactionType.expense,
        '300',
        DateTime(2026, 10, 2),
        category: 'food',
      ),
      tx(
        TransactionType.expense,
        '100',
        DateTime(2026, 10, 3),
        category: 'food',
      ),
      tx(
        TransactionType.expense,
        '100',
        DateTime(2026, 10, 3),
        category: 'fuel',
        account: 'a2',
      ),
      tx(TransactionType.expense, '50', DateTime(2026, 10, 4)),
      // Not income/expense: must never be counted.
      tx(TransactionType.transfer_out, '700', DateTime(2026, 10, 5)),
      tx(
        TransactionType.transfer_in,
        '700',
        DateTime(2026, 10, 5),
        account: 'a2',
      ),
      tx(TransactionType.payment_received, '90', DateTime(2026, 10, 6)),
      // Outside the period or deleted.
      tx(TransactionType.expense, '999', DateTime(2026, 9, 30, 23, 59)),
      tx(TransactionType.expense, '999', DateTime(2026, 11)),
      tx(
        TransactionType.expense,
        '999',
        DateTime(2026, 10, 6),
        deletedAt: DateTime(2026, 10, 7),
      ),
    ];

    test('income, expense and net exclude transfers and out-of-range rows', () {
      final PeriodSummary s = ReportCalculator.summary(data, month);
      expect(s.income, d('1000'));
      expect(s.expense, d('550'));
      expect(s.net, d('450'));
    });

    test('date filter changes the totals', () {
      final ReportPeriod last = ReportPeriod.resolve(DatePreset.lastMonth, now);
      expect(ReportCalculator.summary(data, last).expense, d('999'));
      final ReportPeriod today = ReportPeriod.resolve(DatePreset.today, now);
      final PeriodSummary s = ReportCalculator.summary(data, today);
      expect(s.income, Decimal.zero);
      expect(s.expense, Decimal.zero);
    });

    test('category totals are sorted and shares add up to one', () {
      final List<CategoryTotal> rows = ReportCalculator.categoryTotals(
        data,
        month,
        TransactionType.expense,
      );
      expect(rows.map((CategoryTotal r) => r.categoryId), <String?>[
        'food',
        'fuel',
        null,
      ]);
      expect(rows.first.amount, d('400'));
      expect(
        rows.fold<double>(0, (double a, CategoryTotal r) => a + r.share),
        closeTo(1, 0.0001),
      );
      expect(rows.first.share, closeTo(400 / 550, 0.0001));
    });

    test('income categories are separate from expense categories', () {
      final List<CategoryTotal> rows = ReportCalculator.categoryTotals(
        data,
        month,
        TransactionType.income,
      );
      expect(rows.single.categoryId, 'sal');
      expect(rows.single.share, 1);
    });

    test('account totals cover multiple accounts', () {
      final List<AccountTotal> rows = ReportCalculator.accountTotals(
        data,
        month,
      );
      final AccountTotal a1 = rows.firstWhere(
        (AccountTotal r) => r.accountId == 'a1',
      );
      final AccountTotal a2 = rows.firstWhere(
        (AccountTotal r) => r.accountId == 'a2',
      );
      expect(a1.income, d('1000'));
      expect(a1.expense, d('450'));
      expect(a1.net, d('550'));
      expect(a2.income, Decimal.zero);
      expect(a2.expense, d('100'));
      expect(a2.net, d('-100'));
    });

    test('daily trend has one point per day, including empty days', () {
      final List<TrendPoint> points = ReportCalculator.trend(data, month);
      expect(ReportCalculator.bucketFor(month), TrendBucket.day);
      expect(points, hasLength(31));
      expect(points[0].income, d('1000'));
      expect(points[2].expense, d('200'));
      expect(points[10].expense, Decimal.zero);
    });

    test('a single day is bucketed by hour and a year by month', () {
      final ReportPeriod today = ReportPeriod.resolve(DatePreset.today, now);
      expect(ReportCalculator.bucketFor(today), TrendBucket.hour);
      expect(ReportCalculator.trend(data, today), hasLength(24));
      final ReportPeriod year = ReportPeriod.resolve(DatePreset.thisYear, now);
      final List<TrendPoint> months = ReportCalculator.trend(data, year);
      expect(ReportCalculator.bucketFor(year), TrendBucket.month);
      expect(months, hasLength(12));
      expect(months[9].expense, d('550')); // October
      expect(months[8].expense, d('999')); // September
    });

    test('monthly comparison returns the last six months, oldest first', () {
      final List<TrendPoint> six = ReportCalculator.monthlyComparison(
        data,
        now,
      );
      expect(six, hasLength(6));
      expect(six.first.start, DateTime(2026, 5));
      expect(six.last.start, DateTime(2026, 10));
      expect(six.last.income, d('1000'));
      expect(six[4].expense, d('999'));
    });

    test('empty data gives zeros and no rows', () {
      final PeriodSummary s = ReportCalculator.summary(<Transaction>[], month);
      expect(s.income, Decimal.zero);
      expect(s.net, Decimal.zero);
      expect(
        ReportCalculator.categoryTotals(
          <Transaction>[],
          month,
          TransactionType.expense,
        ),
        isEmpty,
      );
      expect(ReportCalculator.accountTotals(<Transaction>[], month), isEmpty);
      expect(
        ReportCalculator.trend(<Transaction>[], month).every(
          (TrendPoint p) =>
              p.income == Decimal.zero && p.expense == Decimal.zero,
        ),
        isTrue,
      );
    });

    test('keeps cents exact across many small amounts', () {
      final List<Transaction> many = <Transaction>[
        for (int i = 0; i < 100; i++)
          tx(TransactionType.expense, '0.10', DateTime(2026, 10, 2, i % 24, i)),
      ];
      expect(ReportCalculator.summary(many, month).expense, d('10'));
    });
  });
}
