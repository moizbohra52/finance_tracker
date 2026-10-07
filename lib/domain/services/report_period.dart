/// Presets offered by the report date filter.
enum DatePreset {
  today('Today'),
  thisWeek('This week'),
  thisMonth('This month'),
  lastMonth('Last month'),
  thisYear('This year'),
  custom('Custom');

  const DatePreset(this.label);

  final String label;
}

/// A half-open date range: `start <= date < end`. Weeks start on Monday.
class ReportPeriod {
  const ReportPeriod({
    required this.preset,
    required this.start,
    required this.end,
  });

  /// [customStart] and [customEnd] are inclusive calendar days and are only
  /// used for [DatePreset.custom].
  factory ReportPeriod.resolve(
    DatePreset preset,
    DateTime now, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final (DateTime, DateTime) range = switch (preset) {
      DatePreset.today => (
        today,
        DateTime(today.year, today.month, today.day + 1),
      ),
      DatePreset.thisWeek => () {
        final DateTime monday = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - DateTime.monday),
        );
        return (monday, DateTime(monday.year, monday.month, monday.day + 7));
      }(),
      DatePreset.thisMonth => (
        DateTime(today.year, today.month),
        DateTime(today.year, today.month + 1),
      ),
      DatePreset.lastMonth => (
        DateTime(today.year, today.month - 1),
        DateTime(today.year, today.month),
      ),
      DatePreset.thisYear => (DateTime(today.year), DateTime(today.year + 1)),
      DatePreset.custom => () {
        final DateTime s = _day(customStart ?? today);
        final DateTime e = _day(customEnd ?? s);
        final DateTime first = e.isBefore(s) ? e : s;
        final DateTime last = e.isBefore(s) ? s : e;
        return (first, DateTime(last.year, last.month, last.day + 1));
      }(),
    };
    return ReportPeriod(preset: preset, start: range.$1, end: range.$2);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  final DatePreset preset;
  final DateTime start;

  /// Exclusive upper bound.
  final DateTime end;

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);

  /// Inclusive last day, for display.
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  int get days => DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
}
