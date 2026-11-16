import 'dart:convert';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/statement_import.dart';
import 'package:finance_tracker/features/import/controllers/import_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

const String _statement =
    'State Bank of India\n'
    'Txn Date,Description,Debit,Credit,Balance\n'
    '01/11/2026,UPI/Swiggy,450.00,,9550.00\n'
    '02/11/2026,Salary,,"50,000.00",59550.00\n'
    ',Closing balance,,,59550.00\n';

void main() {
  late FakeFinance finance;
  late ImportController controller;

  setUp(() async {
    finance = FakeFinance()..addAccount('SBI', '10000', id: 'sbi');
    controller = ImportController(
      finance.repositories.transactions,
      finance.repositories.accounts,
      finance.repositories.categories,
      FakeAuthRepository(signedIn: true),
      DataChangeNotifier(),
      pickFile: () async => (
        name: 'statement.csv',
        bytes: Uint8List.fromList(utf8.encode(_statement)),
      ),
    );
    await controller.load();
    await controller.chooseFile();
  });
  tearDown(Get.reset);

  Decimal sbiBalance() => FinanceSummaryCalculator.accountBalances(
    finance.accounts,
    finance.transactions,
  )['sbi']!;

  test('reads the statement and guesses its columns', () {
    expect(controller.fileError.value, isNull);
    expect(controller.columns, <ImportField, int>{
      ImportField.date: 0,
      ImportField.note: 1,
      ImportField.debit: 2,
      ImportField.credit: 3,
    });
    final ImportPlan plan = controller.plan.value!;
    expect(plan.transactions, hasLength(2));
    expect(plan.unreadable, 1);
  });

  test('keeps the balance with one adjustment, and a second import adds '
      'nothing', () async {
    expect(await controller.importNow(), isTrue);

    expect(finance.transactions, hasLength(3));
    final Transaction adjustment = finance.transactions.singleWhere(
      (Transaction t) => t.type == TransactionType.adjustment_out,
    );
    expect(adjustment.amount, Decimal.parse('49550'));
    expect(sbiBalance(), Decimal.parse('10000'));

    await controller.load();
    expect(controller.plan.value!.transactions, isEmpty);
    expect(controller.plan.value!.duplicates, 2);
  });

  test('letting the balance change writes no adjustment', () async {
    controller.setKeepBalance('sbi', keep: false);
    expect(await controller.importNow(), isTrue);

    expect(finance.transactions, hasLength(2));
    expect(sbiBalance(), Decimal.parse('59550'));
  });

  test('choosing Amount clears Debit and Credit, and one column is one '
      'field', () {
    controller.setColumn(ImportField.amount, 1);
    expect(controller.columns, <ImportField, int>{
      ImportField.date: 0,
      ImportField.amount: 1,
    });
    // "UPI/Swiggy" is no amount: nothing can be read.
    expect(controller.plan.value!.transactions, isEmpty);
  });
}
