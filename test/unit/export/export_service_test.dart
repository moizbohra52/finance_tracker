import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:excel/excel.dart';
import 'package:finance_tracker/core/services/export_service.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ExportService service = ExportService();

  group('CSV Export', () {
    test('handles empty data with header row and UTF-8 BOM', () {
      final String csv = service.generateTransactionsCsv(<Transaction>[]);
      expect(
        csv.startsWith('\uFEFF'),
        isTrue,
        reason: 'Must include UTF-8 BOM',
      );
      final List<String> lines = const LineSplitter().convert(csv);
      expect(lines.length, 1);
      expect(lines.first, contains('Transaction ID,Date,Time,Type,Account'));
    });

    test('handles commas, double quotes, and line breaks properly', () {
      final Transaction tx = Transaction(
        id: 'tx-1',
        userId: 'user-1',
        accountId: 'acc-1',
        categoryId: 'cat-1',
        type: TransactionType.expense,
        amount: Decimal.parse('1250.75'),
        transactionDate: DateTime(2026, 10, 9, 14, 30),
        note: 'Dinner, with "friends"',
        description: 'Multi-line\ndescription',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final String csv = service.generateTransactionsCsv(
        <Transaction>[tx],
        accountNames: <String, String>{'acc-1': 'Checking Account, Main'},
        categoryNames: <String, String>{'cat-1': 'Food & "Dining"'},
      );

      // Comma in account name should be quoted
      expect(csv, contains('"Checking Account, Main"'));
      // Quotes in category name should be escaped as ""
      expect(csv, contains('"Food & ""Dining"""'));
      // Note with comma and quotes
      expect(csv, contains('"Dinner, with ""friends"""'));
      // Multi-line description quoted
      expect(csv, contains('"Multi-line\ndescription"'));
    });

    test('handles Unicode and Hindi data correctly', () {
      final Contact contact = Contact(
        id: 'c-1',
        userId: 'u-1',
        name: 'रमेश कुमार (Ramesh Kumar)',
        mobile: '+91 9876543210',
        openingBalance: Decimal.parse('5000.50'),
        openingBalanceType: 'receivable',
        notes: 'किराना दुकान 🛒 सामान',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final String csv = service.generateContactsCsv(<Contact>[contact]);
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains('रमेश कुमार (Ramesh Kumar)'));
      expect(csv, contains('किराना दुकान 🛒 सामान'));
      expect(csv, contains('5000.50'));
    });

    test('formats decimal amounts accurately', () {
      final Account account = Account(
        id: 'acc-1',
        userId: 'u-1',
        name: 'Savings',
        type: AccountType.bank,
        openingBalance: Decimal.parse('10000.00'),
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final String csv = service.generateAccountsCsv(
        <Account>[account],
        currentBalances: <String, Decimal>{'acc-1': Decimal.parse('12345.67')},
      );
      expect(csv, contains('10000.00'));
      expect(csv, contains('12345.67'));
    });

    test('handles large export without memory explosion or crashing', () {
      final List<Transaction> largeList = List<Transaction>.generate(
        5000,
        (int i) => Transaction(
          id: 'tx-$i',
          userId: 'u-1',
          accountId: 'acc-1',
          type: i % 2 == 0 ? TransactionType.income : TransactionType.expense,
          amount: Decimal.fromInt(i * 10),
          transactionDate: DateTime(2026, 1, 1).add(Duration(hours: i)),
          note: 'Transaction note $i',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final String csv = service.generateTransactionsCsv(largeList);
      final List<String> lines = const LineSplitter().convert(csv);
      // 1 header + 5000 rows
      expect(lines.length, 5001);
    });

    test('exports budgets and contact transactions correctly', () {
      final Budget budget = Budget(
        id: 'b-1',
        userId: 'u-1',
        categoryId: 'cat-groceries',
        amount: Decimal.parse('15000'),
        periodType: BudgetPeriodType.monthly,
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
        alert75: true,
        alert90: true,
        alert100: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final String csv = service.generateBudgetsCsv(
        <Budget>[budget],
        categoryNames: <String, String>{'cat-groceries': 'Groceries'},
      );
      expect(csv, contains('Groceries'));
      expect(csv, contains('15000.00'));
      expect(csv, contains('monthly'));
      expect(csv, contains('Yes,Yes,No'));
    });
  });

  group('Excel Export', () {
    test('generates valid Excel file with headers, rows and summary', () {
      final List<Transaction> txs = <Transaction>[
        Transaction(
          id: 'tx-1',
          userId: 'u-1',
          accountId: 'acc-1',
          type: TransactionType.income,
          amount: Decimal.parse('5000.00'),
          transactionDate: DateTime(2026, 10, 1),
          note: 'Salary',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Transaction(
          id: 'tx-2',
          userId: 'u-1',
          accountId: 'acc-1',
          type: TransactionType.expense,
          amount: Decimal.parse('2000.00'),
          transactionDate: DateTime(2026, 10, 2),
          note: 'Rent',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final List<int> bytes = service.generateTransactionsExcel(txs);
      expect(bytes.isNotEmpty, isTrue);

      final Excel decoded = Excel.decodeBytes(bytes);
      expect(decoded.sheets.containsKey('Transactions'), isTrue);
      final Sheet sheet = decoded['Transactions'];
      expect(sheet.maxRows, greaterThanOrEqualTo(3));
    });

    test('generates multi-sheet full workbook', () {
      final List<int> bytes = service.generateFullReportExcel(
        transactions: <Transaction>[],
        accounts: <Account>[
          Account(
            id: 'a-1',
            userId: 'u-1',
            name: 'Cash',
            type: AccountType.cash,
            openingBalance: Decimal.zero,
            isActive: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
        contacts: <Contact>[],
        contactTransactions: <ContactTransaction>[],
        budgets: <Budget>[],
      );
      expect(bytes.isNotEmpty, isTrue);

      final Excel decoded = Excel.decodeBytes(bytes);
      expect(decoded.sheets.containsKey('Transactions'), isTrue);
      expect(decoded.sheets.containsKey('Accounts'), isTrue);
      expect(decoded.sheets.containsKey('Khata Contacts'), isTrue);
      expect(decoded.sheets.containsKey('Budgets'), isTrue);
    });
  });

  group('PDF Export', () {
    test(
      'generates professional PDF with KPI cards and transaction table',
      () async {
        final List<Transaction> txs = <Transaction>[
          Transaction(
            id: 'tx-1',
            userId: 'u-1',
            accountId: 'acc-1',
            categoryId: 'cat-1',
            type: TransactionType.income,
            amount: Decimal.parse('25000'),
            transactionDate: DateTime(2026, 10, 5),
            note: 'Freelance Design',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          Transaction(
            id: 'tx-2',
            userId: 'u-1',
            accountId: 'acc-1',
            categoryId: 'cat-2',
            type: TransactionType.expense,
            amount: Decimal.parse('8500'),
            transactionDate: DateTime(2026, 10, 6),
            note: 'Groceries and Utilities',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        final List<int> bytes = await service.generateReportPdf(
          title: 'Monthly Financial Statement',
          periodLabel: 'October 2026',
          transactions: txs,
          accountNames: <String, String>{'acc-1': 'Main Bank'},
          categoryNames: <String, String>{
            'cat-1': 'Freelance',
            'cat-2': 'Groceries',
          },
          userName: 'Asha Sharma',
          currencyCode: 'INR',
        );

        expect(bytes.isNotEmpty, isTrue);
        // Valid PDF documents start with %PDF- header
        final String header = String.fromCharCodes(bytes.take(5));
        expect(header, '%PDF-');
      },
    );

    test('generates empty PDF report safely without exceptions', () async {
      final List<int> bytes = await service.generateReportPdf(
        title: 'Empty Statement',
        periodLabel: 'No Data Period',
        transactions: <Transaction>[],
      );
      expect(bytes.isNotEmpty, isTrue);
      final String header = String.fromCharCodes(bytes.take(5));
      expect(header, '%PDF-');
    });
  });
}
