import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:uuid/uuid.dart';

/// Schedule maths for recurring transactions. Occurrences are always computed
/// from the start date (never by chaining from the previous run), so a rule
/// that starts on the 31st stays on month-end instead of drifting to the 28th.
abstract final class RecurringScheduler {
  /// Occurrences happen at this local hour.
  static const int runHour = 9;

  /// Most occurrences materialised in one run, so a long-unused app does not
  /// create thousands of rows at once. The rest follow on the next run.
  static const int maxPerRun = 366;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Occurrence [index] (0 = the start date).
  static DateTime occurrence(
    DateTime startDate,
    RecurringFrequency frequency,
    int intervalCount,
    int index,
  ) {
    final DateTime s = _day(startDate);
    final int steps = index * intervalCount;
    switch (frequency) {
      case RecurringFrequency.daily:
        return DateTime(s.year, s.month, s.day + steps, runHour);
      case RecurringFrequency.weekly:
        return DateTime(s.year, s.month, s.day + 7 * steps, runHour);
      case RecurringFrequency.monthly:
        return _clampedMonth(s, steps);
      case RecurringFrequency.yearly:
        return _clampedMonth(s, steps * 12);
    }
  }

  /// Adds whole months, clamping to the last day of a shorter month.
  static DateTime _clampedMonth(DateTime start, int months) {
    final int total = start.year * 12 + (start.month - 1) + months;
    final int year = total ~/ 12;
    final int month = total % 12 + 1;
    final int lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      start.day > lastDay ? lastDay : start.day,
      runHour,
    );
  }

  static DateTime _at(RecurringTransaction r, int index) =>
      occurrence(r.startDate, r.frequency, r.intervalCount, index);

  static bool _pastEnd(RecurringTransaction r, DateTime occurrence) =>
      r.endDate != null && _day(occurrence).isAfter(_day(r.endDate!));

  /// The first occurrence at or after [moment], or null when the rule has
  /// ended by then.
  static DateTime? firstOnOrAfter(RecurringTransaction r, DateTime moment) {
    int i = 0;
    while (true) {
      final DateTime o = _at(r, i);
      if (_pastEnd(r, o)) return null;
      if (!o.isBefore(moment)) return o;
      i++;
    }
  }

  /// Occurrences from `nextRunAt` up to [now] that have not run yet, oldest
  /// first, at most [maxPerRun].
  static List<DateTime> due(RecurringTransaction r, DateTime now) {
    if (!r.active || r.deletedAt != null) return const <DateTime>[];
    final List<DateTime> out = <DateTime>[];
    int i = 0;
    while (out.length < maxPerRun) {
      final DateTime o = _at(r, i++);
      if (o.isAfter(now) || _pastEnd(r, o)) break;
      if (!o.isBefore(r.nextRunAt)) out.add(o);
    }
    return out;
  }

  /// The occurrence after [last], or null when the rule has ended.
  static DateTime? nextAfter(RecurringTransaction r, DateTime last) {
    int i = 0;
    while (true) {
      final DateTime o = _at(r, i++);
      if (_pastEnd(r, o)) return null;
      if (o.isAfter(last)) return o;
    }
  }

  /// Id of the notification-center entry announcing the run that ended at
  /// [lastOccurrence]. Deterministic, so the same run announced twice (retry,
  /// two devices) is stored once.
  static String notificationId(String recurringId, DateTime lastOccurrence) =>
      const Uuid().v5(
        Namespace.url.value,
        'recurring-notification:$recurringId:'
        '${lastOccurrence.year}-${lastOccurrence.month}-${lastOccurrence.day}',
      );

  /// Id of the transaction created for one occurrence. Derived from the rule
  /// and the occurrence date, so running the same occurrence twice (retry,
  /// two devices) can only ever produce one transaction.
  static String transactionId(String recurringId, DateTime occurrence) =>
      const Uuid().v5(
        Namespace.url.value,
        'recurring:$recurringId:'
        '${occurrence.year}-${occurrence.month}-${occurrence.day}',
      );
}
