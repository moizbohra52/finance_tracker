import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:intl/intl.dart';

/// Locale-aware display formatting. Keep financial calculations in the domain
/// layer and pass their final values here only for presentation.
abstract final class AppFormatters {
  static String currency(
    num amount, {
    String currencyCode = AppConstants.defaultCurrencyCode,
    String locale = AppConstants.defaultLocale,
  }) => NumberFormat.simpleCurrency(
    locale: locale,
    name: currencyCode,
    decimalDigits: AppConstants.currencyDecimalDigits,
  ).format(amount);

  /// Formats a domain [Decimal] for display only.
  static String money(Decimal amount) => currency(amount.toDouble());

  /// Absolute amount with an explicit sign, e.g. `+₹250.00`.
  static String signedMoney(Decimal amount, {required bool positive}) =>
      '${positive ? '+' : '−'}${money(amount.abs())}';

  static String number(
    num value, {
    int decimalDigits = 2,
    String locale = AppConstants.defaultLocale,
  }) => NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: decimalDigits,
  ).format(value);

  static String date(
    DateTime value, {
    String pattern = 'd MMM y',
    String locale = AppConstants.defaultLocale,
  }) => DateFormat(pattern, locale).format(value);

  static String dateTime(
    DateTime value, {
    String pattern = 'd MMM y, h:mm a',
    String locale = AppConstants.defaultLocale,
  }) => DateFormat(pattern, locale).format(value);

  static String time(DateTime value) => dateTime(value, pattern: 'h:mm a');

  /// "Today", "Yesterday" or the date, for list section headers.
  static String dayLabel(DateTime value, {DateTime? now}) {
    final DateTime today = _dayOnly(now ?? DateTime.now());
    final int diff = today.difference(_dayOnly(value)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return date(value);
  }

  static DateTime _dayOnly(DateTime v) => DateTime(v.year, v.month, v.day);
}
