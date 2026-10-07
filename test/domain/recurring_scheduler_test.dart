import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/recurring_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringTransaction rule({
  RecurringFrequency frequency = RecurringFrequency.monthly,
  int interval = 1,
  DateTime? start,
  DateTime? end,
  DateTime? nextRunAt,
  bool active = true,
}) {
  final DateTime s = start ?? DateTime(2026, 1, 31);
  return RecurringTransaction(
    id: 'r1',
    userId: 'u',
    accountId: 'a1',
    categoryId: null,
    type: TransactionType.expense,
    amount: Decimal.parse('100'),
    frequency: frequency,
    intervalCount: interval,
    startDate: s,
    endDate: end,
    nextRunAt:
        nextRunAt ?? RecurringScheduler.occurrence(s, frequency, interval, 0),
    active: active,
    note: null,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

DateTime at(int y, int m, int d) =>
    DateTime(y, m, d, RecurringScheduler.runHour);

void main() {
  group('occurrence', () {
    test('daily and weekly add whole days', () {
      expect(
        RecurringScheduler.occurrence(
          DateTime(2026, 2, 27),
          RecurringFrequency.daily,
          1,
          3,
        ),
        at(2026, 3, 2),
      );
      expect(
        RecurringScheduler.occurrence(
          DateTime(2026, 12, 28),
          RecurringFrequency.weekly,
          1,
          2,
        ),
        at(2027, 1, 11),
      );
    });

    test('monthly stays on month-end instead of drifting', () {
      final DateTime start = DateTime(2026, 1, 31);
      DateTime nth(int i) => RecurringScheduler.occurrence(
        start,
        RecurringFrequency.monthly,
        1,
        i,
      );
      expect(nth(0), at(2026, 1, 31));
      expect(nth(1), at(2026, 2, 28));
      expect(nth(2), at(2026, 3, 31));
      expect(nth(3), at(2026, 4, 30));
      expect(nth(12), at(2027, 1, 31));
    });

    test('monthly crosses year ends', () {
      expect(
        RecurringScheduler.occurrence(
          DateTime(2026, 11, 15),
          RecurringFrequency.monthly,
          1,
          3,
        ),
        at(2027, 2, 15),
      );
    });

    test('yearly handles 29 February', () {
      final DateTime start = DateTime(2024, 2, 29);
      DateTime nth(int i) =>
          RecurringScheduler.occurrence(start, RecurringFrequency.yearly, 1, i);
      expect(nth(1), at(2025, 2, 28));
      expect(nth(4), at(2028, 2, 29));
    });

    test('custom intervals multiply the unit', () {
      expect(
        RecurringScheduler.occurrence(
          DateTime(2026, 10, 1),
          RecurringFrequency.weekly,
          2,
          3,
        ),
        at(2026, 11, 12),
      );
      expect(
        RecurringScheduler.occurrence(
          DateTime(2026, 10, 1),
          RecurringFrequency.daily,
          45,
          2,
        ),
        at(2026, 12, 30),
      );
      expect(
        RecurringScheduler.occurrence(
          DateTime(2026, 11, 30),
          RecurringFrequency.monthly,
          3,
          1,
        ),
        at(2027, 2, 28),
      );
      expect(
        RecurringScheduler.occurrence(
          DateTime(2026, 5, 1),
          RecurringFrequency.yearly,
          2,
          1,
        ),
        at(2028, 5, 1),
      );
    });
  });

  group('due', () {
    test('nothing is due before the first occurrence', () {
      final RecurringTransaction r = rule(start: DateTime(2026, 10, 10));
      expect(RecurringScheduler.due(r, DateTime(2026, 10, 9, 23)), isEmpty);
      expect(RecurringScheduler.due(r, DateTime(2026, 10, 10, 8)), isEmpty);
    });

    test('an occurrence is due from its run time onwards', () {
      final RecurringTransaction r = rule(start: DateTime(2026, 10, 10));
      expect(RecurringScheduler.due(r, DateTime(2026, 10, 10, 9)), <DateTime>[
        at(2026, 10, 10),
      ]);
    });

    test('catches up every missed occurrence, oldest first', () {
      final RecurringTransaction r = rule(
        frequency: RecurringFrequency.daily,
        start: DateTime(2026, 10, 1),
      );
      expect(RecurringScheduler.due(r, DateTime(2026, 10, 4, 12)), <DateTime>[
        at(2026, 10, 1),
        at(2026, 10, 2),
        at(2026, 10, 3),
        at(2026, 10, 4),
      ]);
    });

    test('skips occurrences that already ran', () {
      final RecurringTransaction r = rule(
        frequency: RecurringFrequency.daily,
        start: DateTime(2026, 10, 1),
        nextRunAt: at(2026, 10, 3),
      );
      expect(RecurringScheduler.due(r, DateTime(2026, 10, 4, 12)), <DateTime>[
        at(2026, 10, 3),
        at(2026, 10, 4),
      ]);
    });

    test('stops at the end date, which is inclusive', () {
      final RecurringTransaction r = rule(
        frequency: RecurringFrequency.daily,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 2),
      );
      expect(RecurringScheduler.due(r, DateTime(2026, 10, 9)), <DateTime>[
        at(2026, 10, 1),
        at(2026, 10, 2),
      ]);
    });

    test('paused rules produce nothing', () {
      final RecurringTransaction r = rule(
        frequency: RecurringFrequency.daily,
        start: DateTime(2026, 10, 1),
        active: false,
      );
      expect(RecurringScheduler.due(r, DateTime(2026, 10, 9)), isEmpty);
    });

    test('a long gap is capped per run and continues next time', () {
      final RecurringTransaction r = rule(
        frequency: RecurringFrequency.daily,
        start: DateTime(2020, 1, 1),
      );
      final List<DateTime> batch = RecurringScheduler.due(
        r,
        DateTime(2026, 10, 7),
      );
      expect(batch, hasLength(RecurringScheduler.maxPerRun));
      final DateTime? next = RecurringScheduler.nextAfter(r, batch.last);
      expect(next, batch.last.add(const Duration(days: 1)));
      final List<DateTime> second = RecurringScheduler.due(
        r.copyWith(nextRunAt: next),
        DateTime(2026, 10, 7),
      );
      expect(second.first, next);
    });
  });

  group('next occurrence', () {
    test('nextAfter returns the following occurrence', () {
      final RecurringTransaction r = rule();
      expect(RecurringScheduler.nextAfter(r, at(2026, 1, 31)), at(2026, 2, 28));
      expect(RecurringScheduler.nextAfter(r, at(2026, 2, 28)), at(2026, 3, 31));
    });

    test('nextAfter is null once past the end date', () {
      final RecurringTransaction r = rule(end: DateTime(2026, 3, 15));
      expect(RecurringScheduler.nextAfter(r, at(2026, 2, 28)), isNull);
    });

    test('firstOnOrAfter finds the next run from any moment', () {
      final RecurringTransaction r = rule(
        frequency: RecurringFrequency.weekly,
        start: DateTime(2026, 10, 5),
      );
      expect(
        RecurringScheduler.firstOnOrAfter(r, DateTime(2026, 10, 7)),
        at(2026, 10, 12),
      );
      expect(
        RecurringScheduler.firstOnOrAfter(r, at(2026, 10, 12)),
        at(2026, 10, 12),
      );
      expect(
        RecurringScheduler.firstOnOrAfter(
          rule(end: DateTime(2026, 2, 1)),
          DateTime(2026, 6),
        ),
        isNull,
      );
    });
  });

  group('duplicate protection', () {
    test('the transaction id depends only on the rule and the occurrence', () {
      final String first = RecurringScheduler.transactionId(
        'r1',
        at(2026, 10, 1),
      );
      expect(RecurringScheduler.transactionId('r1', at(2026, 10, 1)), first);
      // Time of day does not matter, only the date.
      expect(
        RecurringScheduler.transactionId('r1', DateTime(2026, 10, 1, 23)),
        first,
      );
      expect(
        RecurringScheduler.transactionId('r1', at(2026, 10, 2)),
        isNot(first),
      );
      expect(
        RecurringScheduler.transactionId('r2', at(2026, 10, 1)),
        isNot(first),
      );
    });
  });
}
