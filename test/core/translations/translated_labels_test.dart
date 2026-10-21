import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/translations/app_translations.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/recurring_labels.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/widgets/account_list_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

RecurringTransaction _rule(RecurringFrequency frequency, int every) =>
    RecurringTransaction(
      id: 'r1',
      userId: 'u',
      accountId: 'acc-1',
      categoryId: null,
      type: TransactionType.expense,
      amount: Decimal.parse('100'),
      frequency: frequency,
      intervalCount: every,
      startDate: DateTime(2026, 10),
      endDate: null,
      nextRunAt: DateTime(2026, 10),
      active: true,
      note: null,
      createdAt: DateTime(2026, 10),
      updatedAt: DateTime(2026, 10),
    );

void main() {
  setUp(() {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = AppLanguage.hindi.locale;
  });

  tearDown(() => Get.locale = AppLanguage.english.locale);

  test('recurring schedules read in Hindi', () {
    expect(_rule(RecurringFrequency.weekly, 2).scheduleLabel, 'हर 2 हफ़्ते');
    expect(_rule(RecurringFrequency.daily, 1).scheduleLabel, 'रोज़');
    expect(RecurringFrequency.monthly.units, 'महीने');
  });

  test('list headers say today and yesterday in Hindi', () {
    final DateTime now = DateTime(2026, 10, 21, 10);
    expect(AppFormatters.dayLabel(now, now: now), 'आज');
    expect(
      AppFormatters.dayLabel(now.subtract(const Duration(days: 1)), now: now),
      'कल',
    );
  });

  test('account types read in Hindi', () {
    expect(accountTypeLabel(AccountType.cash), 'कैश');
    expect(accountTypeLabel(AccountType.bank), 'बैंक');
  });

  test('English keeps the English schedule', () {
    Get.locale = AppLanguage.english.locale;
    expect(_rule(RecurringFrequency.weekly, 2).scheduleLabel, 'Every 2 weeks');
  });
}
