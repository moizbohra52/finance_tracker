import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/budget_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String v) => Decimal.parse(v);

Budget budget({
  String id = 'b1',
  String? category,
  String amount = '1000',
  BudgetPeriodType type = BudgetPeriodType.monthly,
  DateTime? start,
  DateTime? end,
  bool a75 = true,
  bool a90 = true,
  bool a100 = true,
}) => Budget(
  id: id,
  userId: 'u',
  categoryId: category,
  amount: d(amount),
  periodType: type,
  startDate: start ?? DateTime(2026, 1, 1),
  endDate: end,
  alert75: a75,
  alert90: a90,
  alert100: a100,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Transaction tx(
  String amount, {
  TransactionType type = TransactionType.expense,
  String? category,
  DateTime? date,
  DateTime? deletedAt,
}) => Transaction(
  id: '$type-$amount-$category-$date',
  userId: 'u',
  accountId: 'a1',
  categoryId: category,
  type: type,
  amount: d(amount),
  transactionDate: date ?? DateTime(2026, 10, 5),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  deletedAt: deletedAt,
);

final DateTime now = DateTime(2026, 10, 7, 15);

void main() {
  group('spent and remaining', () {
    test('overall budget counts every expense in the month', () {
      final BudgetStatus s = BudgetCalculator.status(budget(), <Transaction>[
        tx('300', category: 'food'),
        tx('200', category: 'fuel'),
        tx('50'),
      ], now);
      expect(s.spent, d('550'));
      expect(s.remaining, d('450'));
      expect(s.percent, closeTo(55, 0.0001));
      expect(s.level, BudgetLevel.ok);
      expect(s.state, BudgetState.active);
    });

    test('category budget counts only that category', () {
      final BudgetStatus s = BudgetCalculator.status(
        budget(category: 'food'),
        <Transaction>[tx('300', category: 'food'), tx('200', category: 'fuel')],
        now,
      );
      expect(s.spent, d('300'));
      expect(s.remaining, d('700'));
    });

    test('ignores income, transfers, deleted rows and other months', () {
      final BudgetStatus s = BudgetCalculator.status(budget(), <Transaction>[
        tx('100'),
        tx('900', type: TransactionType.income),
        tx('900', type: TransactionType.transfer_out),
        tx('900', deletedAt: DateTime(2026, 10, 6)),
        tx('900', date: DateTime(2026, 9, 30, 23, 59)),
        tx('900', date: DateTime(2026, 11)),
      ], now);
      expect(s.spent, d('100'));
    });

    test('remaining goes negative when over budget', () {
      final BudgetStatus s = BudgetCalculator.status(budget(), <Transaction>[
        tx('1250.50'),
      ], now);
      expect(s.remaining, d('-250.5'));
      expect(s.percent, closeTo(125.05, 0.0001));
      expect(s.level, BudgetLevel.exceeded);
    });

    test('cents are exact', () {
      final List<Transaction> many = <Transaction>[
        for (int i = 0; i < 100; i++)
          tx('0.10', date: DateTime(2026, 10, 1, 1, i)),
      ];
      final BudgetStatus s = BudgetCalculator.status(budget(), many, now);
      expect(s.spent, d('10'));
      expect(s.remaining, d('990'));
    });
  });

  group('thresholds', () {
    List<int> crossed(String spent) => BudgetCalculator.status(
      budget(),
      <Transaction>[tx(spent)],
      now,
    ).crossed;

    test('exactly at a threshold counts, just under does not', () {
      expect(crossed('749.99'), isEmpty);
      expect(crossed('750'), <int>[75]);
      expect(crossed('899.99'), <int>[75]);
      expect(crossed('900'), <int>[75, 90]);
      expect(crossed('999.99'), <int>[75, 90]);
      expect(crossed('1000'), <int>[75, 90, 100]);
      expect(crossed('5000'), <int>[75, 90, 100]);
    });

    test('level is the highest threshold reached', () {
      BudgetLevel level(String spent) => BudgetCalculator.status(
        budget(),
        <Transaction>[tx(spent)],
        now,
      ).level;
      expect(level('100'), BudgetLevel.ok);
      expect(level('800'), BudgetLevel.warning75);
      expect(level('950'), BudgetLevel.warning90);
      expect(level('1000'), BudgetLevel.exceeded);
    });
  });

  group('periods', () {
    test('monthly budgets measure the current calendar month', () {
      final (period, state) = BudgetCalculator.periodFor(budget(), now);
      expect(period.start, DateTime(2026, 10));
      expect(period.end, DateTime(2026, 11));
      expect(state, BudgetState.active);
    });

    test('a monthly budget resets each month', () {
      final List<Transaction> data = <Transaction>[
        tx('900', date: DateTime(2026, 9, 10)),
        tx('100', date: DateTime(2026, 10, 2)),
      ];
      expect(BudgetCalculator.status(budget(), data, now).spent, d('100'));
      expect(
        BudgetCalculator.status(budget(), data, DateTime(2026, 9, 20)).spent,
        d('900'),
      );
    });

    test(
      'a monthly budget that starts later is upcoming with nothing spent',
      () {
        final BudgetStatus s = BudgetCalculator.status(
          budget(start: DateTime(2026, 12, 1)),
          <Transaction>[tx('500')],
          now,
        );
        expect(s.state, BudgetState.upcoming);
        expect(s.spent, Decimal.zero);
        expect(s.period.start, DateTime(2026, 12));
      },
    );

    test('custom budgets include both end days', () {
      final Budget b = budget(
        type: BudgetPeriodType.custom,
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 10),
      );
      final List<Transaction> data = <Transaction>[
        tx('10', date: DateTime(2026, 10, 4, 23, 59)),
        tx('20', date: DateTime(2026, 10, 5)),
        tx('30', date: DateTime(2026, 10, 10, 23, 59)),
        tx('40', date: DateTime(2026, 10, 11)),
      ];
      final BudgetStatus s = BudgetCalculator.status(b, data, now);
      expect(s.spent, d('50'));
      expect(s.state, BudgetState.active);
    });

    test('custom budgets know when they have not started or have ended', () {
      final Budget b = budget(
        type: BudgetPeriodType.custom,
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 10),
      );
      expect(
        BudgetCalculator.periodFor(b, DateTime(2026, 10, 1)).$2,
        BudgetState.upcoming,
      );
      expect(
        BudgetCalculator.periodFor(b, DateTime(2026, 10, 10, 20)).$2,
        BudgetState.active,
      );
      expect(
        BudgetCalculator.periodFor(b, DateTime(2026, 10, 11)).$2,
        BudgetState.ended,
      );
    });

    test('statuses list active budgets first, fullest first', () {
      final List<BudgetStatus> list = BudgetCalculator.statuses(
        <Budget>[
          budget(
            id: 'ended',
            type: BudgetPeriodType.custom,
            start: DateTime(2026, 1, 1),
            end: DateTime(2026, 1, 31),
          ),
          budget(id: 'low', amount: '1000', category: 'x'),
          budget(id: 'high', amount: '100'),
          budget(id: 'future', start: DateTime(2027)),
        ],
        <Transaction>[tx('90')],
        now,
      );
      expect(list.map((BudgetStatus s) => s.budget.id), <String>[
        'high',
        'low',
        'future',
        'ended',
      ]);
    });

    test('window spans every budget period', () {
      final (DateTime, DateTime)? w = BudgetCalculator.window(<Budget>[
        budget(),
        budget(
          id: 'c',
          type: BudgetPeriodType.custom,
          start: DateTime(2026, 8, 15),
          end: DateTime(2026, 8, 20),
        ),
      ], now);
      expect(w!.$1, DateTime(2026, 8, 15));
      expect(w.$2, DateTime(2026, 11));
      expect(BudgetCalculator.window(<Budget>[], now), isNull);
    });
  });

  group('alerts', () {
    BudgetStatus at(String spent, {Budget? b, DateTime? when}) =>
        BudgetCalculator.status(b ?? budget(), <Transaction>[
          tx(spent),
        ], when ?? now);

    test('one alert per crossed threshold', () {
      final List<BudgetAlert> alerts = BudgetCalculator.alertsFor(at('950'));
      expect(alerts.map((BudgetAlert a) => a.threshold), <int>[75, 90]);
    });

    test('disabled thresholds raise nothing', () {
      final List<BudgetAlert> alerts = BudgetCalculator.alertsFor(
        at('1000', b: budget(a75: false, a100: false)),
      );
      expect(alerts.map((BudgetAlert a) => a.threshold), <int>[90]);
    });

    test('the same event always has the same id', () {
      final BudgetAlert first = BudgetCalculator.alertsFor(at('800')).single;
      final BudgetAlert again = BudgetCalculator.alertsFor(
        at('800', when: DateTime(2026, 10, 28)),
      ).single;
      expect(again.id, first.id);
    });

    test('a new period, threshold or budget gets a different id', () {
      final BudgetAlert october = BudgetCalculator.alertsFor(at('800')).single;
      final BudgetAlert november = BudgetCalculator.alertsFor(
        BudgetCalculator.status(budget(), <Transaction>[
          tx('800', date: DateTime(2026, 11, 3)),
        ], DateTime(2026, 11, 20)),
      ).single;
      final BudgetAlert other = BudgetCalculator.alertsFor(
        at('800', b: budget(id: 'b2')),
      ).single;
      final List<BudgetAlert> both = BudgetCalculator.alertsFor(at('950'));
      expect(<String>{
        october.id,
        november.id,
        other.id,
        both[1].id,
      }, hasLength(4));
    });

    test('upcoming budgets raise nothing', () {
      expect(
        BudgetCalculator.alertsFor(
          BudgetCalculator.status(
            budget(start: DateTime(2027), amount: '1'),
            <Transaction>[tx('500')],
            now,
          ),
        ),
        isEmpty,
      );
    });
  });
}
