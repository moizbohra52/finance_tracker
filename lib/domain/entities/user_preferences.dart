import 'package:flutter/foundation.dart';

/// A currency the app can display. Only these are offered in settings, so
/// every amount is formatted with a known symbol and decimal count.
@immutable
class CurrencyOption {
  const CurrencyOption(this.code, this.name, this.decimalDigits);

  /// ISO 4217 code, stored in profiles.currency_code.
  final String code;
  final String name;
  final int decimalDigits;
}

abstract final class Currencies {
  static const CurrencyOption inr = CurrencyOption('INR', 'Indian rupee', 2);

  static const List<CurrencyOption> supported = <CurrencyOption>[
    inr,
    CurrencyOption('USD', 'US dollar', 2),
    CurrencyOption('EUR', 'Euro', 2),
    CurrencyOption('GBP', 'British pound', 2),
    CurrencyOption('AED', 'UAE dirham', 2),
    CurrencyOption('SGD', 'Singapore dollar', 2),
    CurrencyOption('AUD', 'Australian dollar', 2),
    CurrencyOption('CAD', 'Canadian dollar', 2),
    CurrencyOption('JPY', 'Japanese yen', 0),
  ];

  /// Unknown codes fall back to the default, so a bad stored value cannot
  /// break amount display.
  static CurrencyOption byCode(String? code) => supported.firstWhere(
    (CurrencyOption option) => option.code == code,
    orElse: () => inr,
  );
}

/// How dates are shown. [pattern] is what user_settings.date_format stores.
enum DateStyle {
  dayMonthYear('d MMM y', '8 Oct 2026'),
  dayMonthNumeric('dd/MM/yyyy', '08/10/2026'),
  monthDayNumeric('MM/dd/yyyy', '10/08/2026'),
  isoDate('yyyy-MM-dd', '2026-10-08');

  const DateStyle(this.pattern, this.example);

  final String pattern;

  /// Shown beside the option so the choice is clear without reading a pattern.
  final String example;

  static DateStyle fromStored(String? value) => values.firstWhere(
    (DateStyle style) => style.pattern == value,
    orElse: () => dayMonthYear,
  );
}

/// How numbers are grouped. [stored] is what user_settings.number_format holds.
enum NumberStyle {
  indian('indian', 'en_IN', '1,00,000.00'),
  international('international', 'en_US', '100,000.00');

  const NumberStyle(this.stored, this.locale, this.example);

  final String stored;

  /// Intl locale that produces this grouping.
  final String locale;
  final String example;

  static NumberStyle fromStored(String? value) => values.firstWhere(
    (NumberStyle style) => style.stored == value,
    orElse: () => indian,
  );
}

/// The first column of the week in weekly reports and summaries.
enum WeekStart {
  monday('monday', 'Monday', DateTime.monday),
  sunday('sunday', 'Sunday', DateTime.sunday);

  const WeekStart(this.stored, this.label, this.weekday);

  final String stored;
  final String label;

  /// [DateTime.weekday] value of the first day.
  final int weekday;

  static WeekStart fromStored(String? value) => values.firstWhere(
    (WeekStart start) => start.stored == value,
    orElse: () => monday,
  );
}

/// Account display preferences. Currency lives in profiles.currency_code, the
/// rest in user_settings. Read everywhere through AppFormatters and
/// SettingsController, never from a widget.
@immutable
class UserPreferences {
  const UserPreferences({
    this.currencyCode = 'INR',
    this.dateStyle = DateStyle.dayMonthYear,
    this.numberStyle = NumberStyle.indian,
    this.weekStart = WeekStart.monday,
    this.languageCode = 'en',
    this.defaultAccountId,
  });

  static const UserPreferences defaults = UserPreferences();

  final String currencyCode;
  final DateStyle dateStyle;
  final NumberStyle numberStyle;
  final WeekStart weekStart;

  /// Only English is available; stored for when more languages arrive.
  final String languageCode;

  /// Pre-selected account on new transactions. Null means the first account.
  final String? defaultAccountId;

  UserPreferences copyWith({
    String? currencyCode,
    DateStyle? dateStyle,
    NumberStyle? numberStyle,
    WeekStart? weekStart,
    String? languageCode,
    String? defaultAccountId,
    bool clearDefaultAccount = false,
  }) => UserPreferences(
    currencyCode: currencyCode ?? this.currencyCode,
    dateStyle: dateStyle ?? this.dateStyle,
    numberStyle: numberStyle ?? this.numberStyle,
    weekStart: weekStart ?? this.weekStart,
    languageCode: languageCode ?? this.languageCode,
    defaultAccountId: clearDefaultAccount
        ? null
        : (defaultAccountId ?? this.defaultAccountId),
  );

  @override
  bool operator ==(Object other) =>
      other is UserPreferences &&
      other.currencyCode == currencyCode &&
      other.dateStyle == dateStyle &&
      other.numberStyle == numberStyle &&
      other.weekStart == weekStart &&
      other.languageCode == languageCode &&
      other.defaultAccountId == defaultAccountId;

  @override
  int get hashCode => Object.hash(
    currencyCode,
    dateStyle,
    numberStyle,
    weekStart,
    languageCode,
    defaultAccountId,
  );
}
