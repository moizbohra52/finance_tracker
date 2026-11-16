import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/statement_import.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime(2026, 11, 16, 12);

Decimal d(String v) => Decimal.parse(v);

Account _account(String id, String name) => Account(
  id: id,
  userId: 'u1',
  name: name,
  type: AccountType.bank,
  openingBalance: Decimal.zero,
  isActive: true,
  createdAt: _now,
  updatedAt: _now,
);

Category _category(String id, String name, CategoryType type) => Category(
  id: id,
  name: name,
  type: type,
  icon: 'other',
  isSystem: true,
  isActive: true,
  createdAt: _now,
  updatedAt: _now,
);

final List<Account> _accounts = <Account>[
  _account('sbi', 'SBI'),
  _account('cash', 'Cash'),
];
final List<Category> _categories = <Category>[
  _category('food', 'Food & Dining', CategoryType.expense),
  _category('other-exp', 'Other Expense', CategoryType.expense),
  _category('salary', 'Salary', CategoryType.income),
  _category('other-inc', 'Other Income', CategoryType.income),
];

ImportPlan _plan(List<ImportRow> rows, {List<Transaction>? existing}) =>
    StatementImport.plan(
      rows: rows,
      unreadable: 0,
      accounts: _accounts,
      categories: _categories,
      existing: existing ?? <Transaction>[],
      defaultAccountId: 'sbi',
      userId: 'u1',
      now: _now,
    );

ImportRow _expense(String amount, {int day = 1, String note = ''}) => ImportRow(
  date: DateTime(2026, 11, day),
  type: TransactionType.expense,
  amount: d(amount),
  note: note,
);

void main() {
  group('parseAmount', () {
    test('reads Indian statement and app formats', () {
      expect(StatementImport.parseAmount('₹1,234.50'), d('1234.5'));
      expect(StatementImport.parseAmount('Rs. 500'), d('500'));
      expect(StatementImport.parseAmount('1,23,456.789'), d('123456.79'));
      expect(StatementImport.parseAmount('-75'), d('-75'));
      expect(StatementImport.parseAmount('(250.00)'), d('-250'));
    });

    test('Dr is money out and Cr money in, with or without a space', () {
      expect(StatementImport.parseAmount('1,200.00 Dr'), d('-1200'));
      expect(StatementImport.parseAmount('1200.00Cr'), d('1200'));
    });

    test('gives null for anything that is not an amount', () {
      expect(StatementImport.parseAmount(''), isNull);
      expect(StatementImport.parseAmount('Closing balance'), isNull);
      expect(StatementImport.parseAmount('12-11-2026'), isNull);
    });
  });

  group('parseDate', () {
    test('reads the common statement formats', () {
      expect(StatementImport.parseDate('16/11/2026'), DateTime(2026, 11, 16));
      expect(StatementImport.parseDate('16-Nov-2026'), DateTime(2026, 11, 16));
      expect(StatementImport.parseDate('16 Nov 26'), DateTime(2026, 11, 16));
      expect(StatementImport.parseDate('Nov 16, 2026'), DateTime(2026, 11, 16));
      expect(
        StatementImport.parseDate('2026-11-16 10:15:30'),
        DateTime(2026, 11, 16, 10, 15, 30),
      );
      expect(
        StatementImport.parseDate('10/03/2026 02:30 PM'),
        DateTime(2026, 3, 10, 14, 30),
      );
    });

    test('reads an Excel date left as a number', () {
      expect(StatementImport.parseDate('45231'), DateTime(2023, 11, 1));
    });

    test('rejects dates that do not exist and plain text', () {
      expect(StatementImport.parseDate('31/02/2026'), isNull);
      expect(StatementImport.parseDate('Opening balance'), isNull);
      expect(StatementImport.parseDate('2026'), isNull);
    });

    test('is day-first unless a date of the file cannot be', () {
      expect(StatementImport.isDayFirst(<String>['03/04/2026']), isTrue);
      expect(StatementImport.isDayFirst(<String>['25/03/2026']), isTrue);
      expect(
        StatementImport.isDayFirst(<String>['03/04/2026', '03/25/2026']),
        isFalse,
      );
      expect(
        StatementImport.parseDate('03/25/2026', dayFirst: false),
        DateTime(2026, 3, 25),
      );
    });
  });

  test('parseType reads type cells and leaves transfers out', () {
    expect(StatementImport.parseType('DR'), TransactionType.expense);
    expect(StatementImport.parseType('Cr'), TransactionType.income);
    expect(StatementImport.parseType('expense'), TransactionType.expense);
    expect(StatementImport.parseType('Income'), TransactionType.income);
    expect(StatementImport.parseType('transfer_in'), isNull);
    expect(StatementImport.parseType('adjustment_out'), isNull);
  });

  group('a bank statement', () {
    final List<List<String>> raw = <List<String>>[
      <String>['State Bank of India'],
      <String>['Account No', '00001234'],
      <String>[''],
      <String>[
        'Txn Date',
        'Value Date',
        'Description',
        'Ref No',
        'Debit',
        'Credit',
        'Balance',
      ],
      <String>[
        '01/11/2026',
        '01/11/2026',
        'UPI/Swiggy',
        '1',
        '450.00',
        '',
        '9,550.00',
      ],
      <String>[
        '02/11/2026',
        '02/11/2026',
        'Salary',
        '2',
        '',
        '50,000.00',
        '59,550.00',
      ],
      <String>['', '', 'Closing balance', '', '', '', '59,550.00'],
    ];

    test('finds the header below the account details', () {
      final ImportTable table = StatementImport.table(raw)!;
      expect(table.headers.first, 'Txn Date');
      expect(table.rows, hasLength(3));
      expect(StatementImport.guessColumns(table.headers), <ImportField, int>{
        ImportField.date: 0,
        ImportField.note: 2,
        ImportField.debit: 4,
        ImportField.credit: 5,
      });
    });

    test('reads debits as expenses, credits as income, skips the total', () {
      final ImportTable table = StatementImport.table(raw)!;
      final ({List<ImportRow> rows, int unreadable}) read =
          StatementImport.read(
            table,
            StatementImport.guessColumns(table.headers),
          );
      expect(read.unreadable, 1);
      expect(read.rows.map((ImportRow r) => (r.type, r.amount)), <Object>[
        (TransactionType.expense, d('450')),
        (TransactionType.income, d('50000')),
      ]);
      expect(read.rows.first.note, 'UPI/Swiggy');
    });
  });

  test("this app's own export maps every column", () {
    final List<String> headers = <String>[
      'Transaction ID',
      'Date',
      'Time',
      'Type',
      'Account',
      'Category',
      'Amount',
      'Payment Method',
      'Note',
      'Description',
    ];
    expect(StatementImport.guessColumns(headers), <ImportField, int>{
      ImportField.date: 1,
      ImportField.type: 3,
      ImportField.account: 4,
      ImportField.category: 5,
      ImportField.amount: 6,
      ImportField.note: 8,
    });
  });

  group('plan', () {
    test('matches accounts and categories by name, else the defaults', () {
      final ImportPlan plan = _plan(<ImportRow>[
        ImportRow(
          date: DateTime(2026, 11, 1),
          type: TransactionType.expense,
          amount: d('120'),
          category: 'food & dining',
          account: 'Cash',
        ),
        ImportRow(
          date: DateTime(2026, 11, 2),
          type: TransactionType.income,
          amount: d('900'),
          category: 'Freelance',
          account: 'HDFC',
        ),
      ]);
      expect(
        plan.transactions.map((Transaction t) => (t.accountId, t.categoryId)),
        <Object>[('cash', 'food'), ('sbi', 'other-inc')],
      );
    });

    test('skips entries already in the app, one for one', () {
      final ImportPlan first = _plan(<ImportRow>[_expense('450')]);
      final Transaction manual = first.transactions.single;
      // Same account, day, type and amount, entered by hand earlier.
      final Transaction entered = Transaction(
        id: 'manual',
        userId: 'u1',
        accountId: 'sbi',
        type: TransactionType.expense,
        amount: d('450.00'),
        transactionDate: DateTime(2026, 11, 1, 19, 30),
        createdAt: _now,
        updatedAt: _now,
      );
      expect(manual.id, isNot('manual'));

      // Two ₹450 rows in the file and one in the app: one is new.
      final ImportPlan plan = _plan(
        <ImportRow>[_expense('450'), _expense('450')],
        existing: <Transaction>[entered],
      );
      expect(plan.duplicates, 1);
      expect(plan.transactions, hasLength(1));
    });

    test('importing the same file again adds nothing, even after an edit', () {
      final List<ImportRow> rows = <ImportRow>[
        _expense('20', note: 'chai'),
        _expense('20', note: 'chai'),
        _expense('300', day: 3),
      ];
      final ImportPlan first = _plan(rows);
      expect(first.transactions, hasLength(3));

      final List<Transaction> saved = <Transaction>[
        // The user corrected one imported entry's amount.
        first.transactions[0].copyWith(amount: d('25')),
        ...first.transactions.skip(1),
      ];
      final ImportPlan again = _plan(rows, existing: saved);
      expect(again.transactions, isEmpty);
      expect(again.duplicates, 3);
    });

    test('a longer statement adds only its new rows', () {
      final ImportPlan first = _plan(<ImportRow>[_expense('20', note: 'chai')]);
      final ImportPlan longer = _plan(<ImportRow>[
        _expense('20', note: 'chai'),
        _expense('20', note: 'chai'),
      ], existing: first.transactions);
      expect(longer.transactions, hasLength(1));
    });

    test('sums each account and finds its earliest row', () {
      final ImportPlan plan = _plan(<ImportRow>[
        _expense('450', day: 5),
        ImportRow(
          date: DateTime(2026, 11, 2),
          type: TransactionType.income,
          amount: d('50000'),
        ),
      ]);
      final ImportAccountChange sbi = plan.accounts['sbi']!;
      expect(sbi.net, d('49550'));
      expect(sbi.earliest, DateTime(2026, 11, 2));
      expect(sbi.count, 2);
    });
  });

  group('adjustment', () {
    test('takes back the net just before the imported history', () {
      final Transaction t = StatementImport.adjustment(
        accountId: 'sbi',
        change: ImportAccountChange(d('49550'), DateTime(2026, 11, 2), 2),
        note: 'Import adjustment',
        userId: 'u1',
        now: _now,
      )!;
      expect(t.type, TransactionType.adjustment_out);
      expect(t.amount, d('49550'));
      expect(t.transactionDate, DateTime(2026, 11, 1, 23, 59));

      final Transaction back = StatementImport.adjustment(
        accountId: 'sbi',
        change: ImportAccountChange(d('-450'), DateTime(2026, 11, 2), 1),
        note: 'Import adjustment',
        userId: 'u1',
        now: _now,
      )!;
      expect(back.type, TransactionType.adjustment_in);
      expect(back.amount, d('450'));
    });

    test('is not needed when the import does not move the balance', () {
      expect(
        StatementImport.adjustment(
          accountId: 'sbi',
          change: ImportAccountChange(Decimal.zero, DateTime(2026, 11, 2), 2),
          note: 'Import adjustment',
          userId: 'u1',
          now: _now,
        ),
        isNull,
      );
    });
  });
}
