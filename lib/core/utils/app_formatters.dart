import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:intl/intl.dart';

/// Locale-aware display formatting. Keep financial calculations in the domain
/// layer and pass their final values here only for presentation.
///
/// Currency, number and date styles follow the account's preferences, so
/// every amount and date in the app changes together when a setting does.
/// Widgets never choose a symbol, locale or pattern themselves.
abstract final class AppFormatters {
  /// The active account's preferences. SettingsController sets this when the
  /// preferences load or change, and resets it at sign-out.
  static UserPreferences preferences = UserPreferences.defaults;

  static String currency(num amount, {String? currencyCode, String? locale}) {
    final CurrencyOption option = Currencies.byCode(
      currencyCode ?? preferences.currencyCode,
    );
    return NumberFormat.simpleCurrency(
      locale: locale ?? preferences.numberStyle.locale,
      name: option.code,
      decimalDigits: option.decimalDigits,
    ).format(amount);
  }

  /// Formats a domain [Decimal] for display only.
  static String money(Decimal amount) => currency(amount.toDouble());

  /// Absolute amount with an explicit sign, e.g. `+₹250.00`.
  static String signedMoney(Decimal amount, {required bool positive}) =>
      '${positive ? '+' : '−'}${money(amount.abs())}';

  static String number(num value, {int decimalDigits = 2, String? locale}) =>
      NumberFormat.decimalPatternDigits(
        locale: locale ?? preferences.numberStyle.locale,
        decimalDigits: decimalDigits,
      ).format(value);

  /// [pattern] overrides the account's date style for fixed labels such as
  /// chart axes ('MMM') and month titles ('MMMM y').
  static String date(
    DateTime value, {
    String? pattern,
    String locale = AppConstants.defaultLocale,
  }) => DateFormat(
    pattern ?? preferences.dateStyle.pattern,
    locale,
  ).format(value);

  static String dateTime(
    DateTime value, {
    String? pattern,
    String locale = AppConstants.defaultLocale,
  }) => DateFormat(
    pattern ?? '${preferences.dateStyle.pattern}, h:mm a',
    locale,
  ).format(value);

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
