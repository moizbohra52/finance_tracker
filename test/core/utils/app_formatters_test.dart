import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN');
    await initializeDateFormatting('en_US');
  });

  tearDown(() => AppFormatters.preferences = UserPreferences.defaults);

  void use(UserPreferences preferences) =>
      AppFormatters.preferences = preferences;

  group('currency', () {
    test('defaults to Indian rupees with lakh grouping', () {
      expect(AppFormatters.money(Decimal.parse('100000')), '₹1,00,000.00');
    });

    test('follows the selected currency and its number style', () {
      use(
        const UserPreferences(
          currencyCode: 'USD',
          numberStyle: NumberStyle.international,
        ),
      );
      expect(AppFormatters.money(Decimal.parse('100000')), '\$100,000.00');
    });

    test('a currency with no decimals is shown without them', () {
      use(
        const UserPreferences(
          currencyCode: 'JPY',
          numberStyle: NumberStyle.international,
        ),
      );
      expect(AppFormatters.money(Decimal.parse('1500')), '¥1,500');
    });

    test('an unknown code falls back to rupees', () {
      expect(Currencies.byCode('XXX'), Currencies.inr);
      expect(Currencies.byCode(null), Currencies.inr);
    });

    test('signed amounts keep their sign outside the symbol', () {
      expect(
        AppFormatters.signedMoney(Decimal.parse('250'), positive: true),
        '+₹250.00',
      );
      expect(
        AppFormatters.signedMoney(Decimal.parse('250'), positive: false),
        '−₹250.00',
      );
    });
  });

  group('numbers', () {
    test('indian style groups by lakh and crore', () {
      expect(AppFormatters.number(12345678, decimalDigits: 0), '1,23,45,678');
    });

    test('international style groups by thousand', () {
      use(const UserPreferences(numberStyle: NumberStyle.international));
      expect(AppFormatters.number(12345678, decimalDigits: 0), '12,345,678');
    });
  });

  group('dates', () {
    final DateTime day = DateTime(2026, 10, 8, 14, 5);

    test('defaults to day, short month, year', () {
      expect(AppFormatters.date(day), '8 Oct 2026');
    });

    test('each date style renders its own pattern', () {
      use(const UserPreferences(dateStyle: DateStyle.dayMonthNumeric));
      expect(AppFormatters.date(day), '08/10/2026');

      use(const UserPreferences(dateStyle: DateStyle.monthDayNumeric));
      expect(AppFormatters.date(day), '10/08/2026');

      use(const UserPreferences(dateStyle: DateStyle.isoDate));
      expect(AppFormatters.date(day), '2026-10-08');
    });

    test('an explicit pattern overrides the account style', () {
      use(const UserPreferences(dateStyle: DateStyle.isoDate));
      expect(AppFormatters.date(day, pattern: 'MMM'), 'Oct');
      expect(AppFormatters.date(day, pattern: 'MMMM y'), 'October 2026');
    });

    test('date-time adds the time to the account style', () {
      expect(AppFormatters.dateTime(day), '8 Oct 2026, 2:05 pm');
      use(const UserPreferences(dateStyle: DateStyle.isoDate));
      expect(AppFormatters.dateTime(day), '2026-10-08, 2:05 pm');
    });
  });

  group('preferences', () {
    test('unknown stored values fall back to the defaults', () {
      expect(DateStyle.fromStored('mm-dd'), DateStyle.dayMonthYear);
      expect(DateStyle.fromStored(null), DateStyle.dayMonthYear);
      expect(NumberStyle.fromStored('martian'), NumberStyle.indian);
      expect(WeekStart.fromStored(null), WeekStart.monday);
    });

    test('stored values round-trip', () {
      for (final DateStyle style in DateStyle.values) {
        expect(DateStyle.fromStored(style.pattern), style);
      }
      for (final NumberStyle style in NumberStyle.values) {
        expect(NumberStyle.fromStored(style.stored), style);
      }
      for (final WeekStart start in WeekStart.values) {
        expect(WeekStart.fromStored(start.stored), start);
      }
    });

    test('first day of the week maps to the matching weekday', () {
      expect(WeekStart.monday.weekday, DateTime.monday);
      expect(WeekStart.sunday.weekday, DateTime.sunday);
    });

    test('copyWith can clear the default account', () {
      const UserPreferences chosen = UserPreferences(defaultAccountId: 'acc-2');
      expect(
        chosen.copyWith(clearDefaultAccount: true).defaultAccountId,
        isNull,
      );
      expect(chosen.copyWith(currencyCode: 'USD').defaultAccountId, 'acc-2');
    });

    test('value equality drives change detection', () {
      expect(
        const UserPreferences(currencyCode: 'USD'),
        const UserPreferences(currencyCode: 'USD'),
      );
      expect(
        const UserPreferences(currencyCode: 'USD') ==
            const UserPreferences(currencyCode: 'EUR'),
        isFalse,
      );
    });
  });
}
