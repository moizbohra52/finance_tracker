import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:intl/intl.dart';

/// Locale-aware display formatting. Keep financial calculations in the domain
/// layer and pass their final values here only for presentation.
abstract final class AppFormatters {
  static String currency(
    num amount, {
    String currencyCode = AppConstants.defaultCurrencyCode,
    String locale = AppConstants.defaultLocale,
  }) => NumberFormat.currency(
    locale: locale,
    name: currencyCode,
    decimalDigits: AppConstants.currencyDecimalDigits,
  ).format(amount);

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
}
