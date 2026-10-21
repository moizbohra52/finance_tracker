import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/controller/calendar_controller.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';

final DateTime _now = DateTime.now();
final DateTime _thisMonth = DateTime(_now.year, _now.month);

DateTime _day(int day, {int monthOffset = 0}) =>
    DateTime(_now.year, _now.month + monthOffset, day, 12);

void main() {
  late FakeFinance finance;
  late CalendarController controller;

  setUp(() {
    finance = FakeFinance()..addAccount('Cash', '0');
    finance
      ..addTransaction(
        id: 'food-3',
        type: TransactionType.expense,
        amount: '250',
        categoryId: 'cat-food',
        date: _day(3),
      )
      ..addTransaction(
        id: 'taxi-3',
        type: TransactionType.expense,
        amount: '150',
        date: _day(3),
      )
      ..addTransaction(
        id: 'salary-5',
        type: TransactionType.income,
        amount: '5000',
        categoryId: 'cat-salary',
        date: _day(5),
      )
      ..addTransaction(
        id: 'last-month',
        type: TransactionType.expense,
        amount: '400',
        date: _day(10, monthOffset: -1),
      );
    controller = CalendarController(
      finance.repositories.transactions,
      finance.repositories.accounts,
      finance.repositories.categories,
      DataChangeNotifier(),
    );
  });

  test('totals each day and the month', () async {
    await controller.load();

    expect(controller.month.value, _thisMonth);
    expect(
      controller.days.length,
      DateUtils.getDaysInMonth(_now.year, _now.month),
    );
    expect(controller.days[2].expense, Decimal.parse('400'));
    expect(controller.days[4].income, Decimal.parse('5000'));
    expect(controller.days[0].expense, Decimal.zero);
    expect(controller.summary.value.expense, Decimal.parse('400'));
    expect(controller.summary.value.income, Decimal.parse('5000'));
  });

  test('a chosen day lists only its transactions', () async {
    await controller.load();
    controller.selectDay(_day(3));

    expect(controller.dayItems.map((Transaction t) => t.id).toSet(), <String>{
      'food-3',
      'taxi-3',
    });
    controller.selectDay(_day(4));
    expect(controller.dayItems, isEmpty);
  });

  test('moving to another month loads that month', () async {
    await controller.load();
    await controller.previousMonth();

    expect(controller.month.value, DateTime(_now.year, _now.month - 1));
    expect(controller.summary.value.expense, Decimal.parse('400'));
    expect(controller.selectedDay.value, DateTime(_now.year, _now.month - 1));

    await controller.nextMonth();
    expect(controller.month.value, _thisMonth);
    expect(
      controller.selectedDay.value,
      DateTime(_now.year, _now.month, _now.day),
      reason: 'the current month opens on today',
    );
  });

  test('a failed load shows the error', () async {
    finance.nextError = const NetworkFailure();
    await controller.load();

    expect(controller.error.value, const NetworkFailure().message);
    expect(controller.isLoading.value, isFalse);
  });

  test('blank cells before the 1st follow the first day of the week', () {
    // 1 October 2026 is a Thursday.
    final DateTime october = DateTime(2026, 10);
    expect(CalendarController.leadingBlanks(october, DateTime.monday), 3);
    expect(CalendarController.leadingBlanks(october, DateTime.sunday), 4);
    // 1 June 2026 is a Monday.
    expect(
      CalendarController.leadingBlanks(DateTime(2026, 6), DateTime.monday),
      0,
    );
  });
}
