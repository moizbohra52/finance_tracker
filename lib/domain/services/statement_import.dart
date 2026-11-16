import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:uuid/uuid.dart';

/// The columns an import reads. The money is in [amount], or in [debit] and
/// [credit] (a bank statement's two columns).
enum ImportField { date, amount, debit, credit, type, category, note, account }

/// A file's rows as text, below its header row.
class ImportTable {
  const ImportTable(this.headers, this.rows);

  final List<String> headers;
  final List<List<String>> rows;
}

/// One row of the file the import could read: an income or an expense.
class ImportRow {
  const ImportRow({
    required this.date,
    required this.type,
    required this.amount,
    this.category = '',
    this.note = '',
    this.account = '',
  });

  final DateTime date;
  final TransactionType type;

  /// Positive; [type] says which way the money went.
  final Decimal amount;
  final String category;
  final String note;
  final String account;
}

/// What one account gains from an import.
class ImportAccountChange {
  const ImportAccountChange(this.net, this.earliest, this.count);

  /// Signed: income adds, expense subtracts.
  final Decimal net;
  final DateTime earliest;
  final int count;
}

class ImportPlan {
  const ImportPlan({
    required this.transactions,
    required this.duplicates,
    required this.unreadable,
    required this.accounts,
  });

  /// New rows to write, without any balance adjustment.
  final List<Transaction> transactions;

  /// Rows already in the app (same account, day, type and amount, or the
  /// same row imported before).
  final int duplicates;

  /// Rows without a readable date or amount: totals, blanks, transfers.
  final int unreadable;
  final Map<String, ImportAccountChange> accounts;
}

/// Reads a CSV or Excel file of transactions (a bank statement, another
/// app's export, this app's export) into income and expense rows, and plans
/// which of them are new. Pure: the file is read and the rows are written
/// elsewhere (ImportController).
abstract final class StatementImport {
  static const Uuid _uuid = Uuid();

  // Checked in this order, and each header goes to one field only, so
  // "Debit Amount" is a debit and "Dr/Cr" a type, not an amount.
  static final Map<ImportField, RegExp> _headerPatterns = <ImportField, RegExp>{
    ImportField.date: RegExp(r'date', caseSensitive: false),
    ImportField.type: RegExp(
      r'^\s*type\s*$|txn\s*type|transaction\s*type|dr\s*/\s*cr|cr\s*/\s*dr',
      caseSensitive: false,
    ),
    ImportField.debit: RegExp(
      r'debit|withdraw|\bdr\b|money\s*out|paid\s*out',
      caseSensitive: false,
    ),
    ImportField.credit: RegExp(
      r'credit|deposit|\bcr\b|money\s*in|paid\s*in',
      caseSensitive: false,
    ),
    ImportField.amount: RegExp(r'amount|\bamt\b', caseSensitive: false),
    ImportField.category: RegExp(r'categor', caseSensitive: false),
    ImportField.note: RegExp(
      r'note|narration|description|particular|remark|detail|memo|payee|merchant',
      caseSensitive: false,
    ),
    ImportField.account: RegExp(
      r'^\s*account\s*$|account\s*name|wallet',
      caseSensitive: false,
    ),
  };

  static final RegExp _balanceHeader = RegExp('balance', caseSensitive: false);

  /// Bank statements open with account details; the header is the first row
  /// that names a date and some money column.
  static ImportTable? table(List<List<String>> raw) {
    final List<List<String>> rows = raw
        .where((List<String> r) => r.any((String c) => c.trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) return null;
    int header = 0;
    for (int i = 0; i < rows.length && i < 30; i++) {
      if (hasMoneyAndDate(guessColumns(rows[i]))) {
        header = i;
        break;
      }
    }
    final List<String> headers = <String>[
      for (int i = 0; i < rows[header].length; i++)
        rows[header][i].trim().isEmpty
            ? 'Column ${i + 1}'
            : rows[header][i].trim(),
    ];
    return ImportTable(headers, rows.sublist(header + 1));
  }

  static Map<ImportField, int> guessColumns(List<String> headers) {
    final Map<ImportField, int> columns = <ImportField, int>{};
    final Set<int> taken = <int>{};
    for (final MapEntry<ImportField, RegExp> field in _headerPatterns.entries) {
      for (int i = 0; i < headers.length; i++) {
        if (taken.contains(i) || !field.value.hasMatch(headers[i])) continue;
        // A running balance is never the transaction's money.
        if (_isMoney(field.key) && _balanceHeader.hasMatch(headers[i])) {
          continue;
        }
        columns[field.key] = i;
        taken.add(i);
        break;
      }
    }
    return columns;
  }

  static bool _isMoney(ImportField f) =>
      f == ImportField.amount ||
      f == ImportField.debit ||
      f == ImportField.credit;

  static bool hasMoneyAndDate(Map<ImportField, int> columns) =>
      columns.containsKey(ImportField.date) && columns.keys.any(_isMoney);

  /// The file's rows as income and expense. Rows without a readable date,
  /// amount or type (totals, blank lines, transfers) are only counted.
  static ({List<ImportRow> rows, int unreadable}) read(
    ImportTable table,
    Map<ImportField, int> columns,
  ) {
    String cell(List<String> row, ImportField field) {
      final int? i = columns[field];
      return i == null || i >= row.length ? '' : row[i].trim();
    }

    final bool dayFirst = isDayFirst(
      table.rows.map((List<String> r) => cell(r, ImportField.date)),
    );
    final bool split =
        columns.containsKey(ImportField.debit) ||
        columns.containsKey(ImportField.credit);
    final List<ImportRow> rows = <ImportRow>[];
    int unreadable = 0;
    for (final List<String> row in table.rows) {
      final DateTime? date = parseDate(
        cell(row, ImportField.date),
        dayFirst: dayFirst,
      );
      final ({TransactionType type, Decimal amount})? money = split
          ? _fromDebitCredit(
              parseAmount(cell(row, ImportField.debit)),
              parseAmount(cell(row, ImportField.credit)),
            )
          : _fromAmount(
              parseAmount(cell(row, ImportField.amount)),
              columns.containsKey(ImportField.type)
                  ? cell(row, ImportField.type)
                  : null,
            );
      if (date == null || money == null) {
        unreadable++;
        continue;
      }
      rows.add(
        ImportRow(
          date: date,
          type: money.type,
          amount: money.amount,
          category: cell(row, ImportField.category),
          note: cell(row, ImportField.note),
          account: cell(row, ImportField.account),
        ),
      );
    }
    return (rows: rows, unreadable: unreadable);
  }

  static ({TransactionType type, Decimal amount})? _fromDebitCredit(
    Decimal? debit,
    Decimal? credit,
  ) {
    if (debit != null && debit != Decimal.zero) {
      return (type: TransactionType.expense, amount: debit.abs());
    }
    if (credit != null && credit != Decimal.zero) {
      return (type: TransactionType.income, amount: credit.abs());
    }
    return null;
  }

  /// [typeText] is null without a type column: the sign decides then.
  static ({TransactionType type, Decimal amount})? _fromAmount(
    Decimal? amount,
    String? typeText,
  ) {
    if (amount == null || amount == Decimal.zero) return null;
    final TransactionType? type = typeText == null || typeText.isEmpty
        ? (amount < Decimal.zero
              ? TransactionType.expense
              : TransactionType.income)
        : parseType(typeText);
    return type == null ? null : (type: type, amount: amount.abs());
  }

  /// Income or expense from a type cell ("Expense", "Dr", "Credit"...).
  /// Transfers, adjustments and opening balances give null: as two rows
  /// they would count the same money twice.
  static TransactionType? parseType(String text) {
    final String t = text.trim().toLowerCase();
    if (RegExp('transfer|adjust|opening').hasMatch(t)) return null;
    if (RegExp(
      r'\b(income|credit|cr|deposit|received|receipt)\b',
    ).hasMatch(t)) {
      return TransactionType.income;
    }
    if (RegExp(
      r'\b(expense|debit|dr|withdrawal|paid|payment|spent)\b',
    ).hasMatch(t)) {
      return TransactionType.expense;
    }
    return null;
  }

  /// "₹1,234.50", "Rs. 500", "(250.00)", "1,200.00 Dr", "-75". Signed: a
  /// minus, brackets or Dr make it negative. Rounded to paise.
  static Decimal? parseAmount(String text) {
    String t = text.trim();
    if (t.isEmpty) return null;
    bool negative = false;
    if (t.startsWith('(') && t.endsWith(')')) {
      negative = true;
      t = t.substring(1, t.length - 1);
    }
    final RegExpMatch? marker = RegExp(
      r'\s*(cr|dr)\.?$',
      caseSensitive: false,
    ).firstMatch(t);
    if (marker != null) {
      negative = marker.group(1)!.toLowerCase() == 'dr';
      t = t.substring(0, marker.start);
    }
    t = t.replaceAll(RegExp(r'rs\.?|inr|₹|,|\s', caseSensitive: false), '');
    if (t.startsWith('-')) {
      negative = !negative;
      t = t.substring(1);
    } else if (t.startsWith('+')) {
      t = t.substring(1);
    }
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
    final Decimal value = Decimal.parse(t).round(scale: 2);
    return negative ? -value : value;
  }

  static const List<String> _months = <String>[
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  static final RegExp _iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})');
  static final RegExp _numeric = RegExp(
    r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})',
  );
  static final RegExp _dayMonthName = RegExp(
    r'^(\d{1,2})[-\s/]+([a-z]{3,9})\.?[-\s/,]+(\d{2,4})',
    caseSensitive: false,
  );
  static final RegExp _monthNameDay = RegExp(
    r'^([a-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{2,4})',
    caseSensitive: false,
  );
  static final RegExp _time = RegExp(
    r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?',
    caseSensitive: false,
  );

  /// 12/03/2026 is 12 March in India. A file is month-first only when one of
  /// its dates cannot be day-first (03/25/2026).
  static bool isDayFirst(Iterable<String> samples) {
    for (final String s in samples) {
      final RegExpMatch? m = _numeric.firstMatch(s.trim());
      if (m == null) continue;
      if (int.parse(m.group(1)!) > 12) return true;
      if (int.parse(m.group(2)!) > 12) return false;
    }
    return true;
  }

  static DateTime? parseDate(String text, {bool dayFirst = true}) {
    final String t = text.trim();
    if (t.isEmpty) return null;
    // An Excel cell left as a number: days since 30 Dec 1899.
    final double? serial = double.tryParse(t);
    if (serial != null) {
      if (serial < 20000 || serial > 80000) return null;
      final DateTime base = DateTime(1899, 12, 30);
      return DateTime(base.year, base.month, base.day + serial.floor());
    }
    int? year, month, day;
    RegExpMatch? m = _iso.firstMatch(t);
    if (m != null) {
      year = int.parse(m.group(1)!);
      month = int.parse(m.group(2)!);
      day = int.parse(m.group(3)!);
    } else if ((m = _numeric.firstMatch(t)) != null) {
      final int a = int.parse(m!.group(1)!);
      final int b = int.parse(m.group(2)!);
      day = dayFirst ? a : b;
      month = dayFirst ? b : a;
      year = int.parse(m.group(3)!);
    } else if ((m = _dayMonthName.firstMatch(t)) != null) {
      day = int.parse(m!.group(1)!);
      month = _month(m.group(2)!);
      year = int.parse(m.group(3)!);
    } else if ((m = _monthNameDay.firstMatch(t)) != null) {
      month = _month(m!.group(1)!);
      day = int.parse(m.group(2)!);
      year = int.parse(m.group(3)!);
    }
    if (year == null || month == null || day == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final RegExpMatch? clock = _time.firstMatch(t.substring(m!.end));
    int hour = clock == null ? 0 : int.parse(clock.group(1)!);
    final int minute = clock == null ? 0 : int.parse(clock.group(2)!);
    final int second = int.tryParse(clock?.group(3) ?? '') ?? 0;
    final String? meridiem = clock?.group(4)?.toLowerCase();
    if (meridiem == 'pm' && hour < 12) hour += 12;
    if (meridiem == 'am' && hour == 12) hour = 0;
    final DateTime date = DateTime(year, month, day, hour, minute, second);
    // 31/02 would roll into March: not a date.
    return date.month == month && date.day == day ? date : null;
  }

  // The patterns only pass names of 3+ letters.
  static int? _month(String name) {
    final int i = _months.indexOf(name.toLowerCase().substring(0, 3));
    return i < 0 ? null : i + 1;
  }

  /// Which [rows] are new, and the transactions to write for them. A row is
  /// already in the app when [existing] has as many entries with the same
  /// account, day, type and amount as the file has before it, or when this
  /// row was imported before (ids are derived from the row, so importing a
  /// file twice, or again after editing an imported entry, adds nothing).
  ///
  /// The account column is matched by name to [accounts], else
  /// [defaultAccountId]; the category by name among [categories] of the
  /// row's type, else "Other Income" / "Other Expense", else none.
  static ImportPlan plan({
    required List<ImportRow> rows,
    required int unreadable,
    required List<Account> accounts,
    required List<Category> categories,
    required List<Transaction> existing,
    required String defaultAccountId,
    required String userId,
    required DateTime now,
  }) {
    String day(DateTime d) => '${d.year}-${d.month}-${d.day}';
    String contentKey(String account, DateTime date, Object type, Decimal a) =>
        '$account|${day(date)}|$type|$a';

    final Map<String, int> inApp = <String, int>{};
    final Map<String, String> keyOfId = <String, String>{};
    for (final Transaction t in existing) {
      if (t.deletedAt != null) continue;
      final String key = contentKey(
        t.accountId,
        t.transactionDate,
        t.type,
        t.amount,
      );
      keyOfId[t.id] = key;
      inApp[key] = (inApp[key] ?? 0) + 1;
    }

    final Map<String, int> seen = <String, int>{};
    final List<Transaction> out = <Transaction>[];
    final Map<String, ImportAccountChange> changes =
        <String, ImportAccountChange>{};
    int duplicates = 0;
    for (final ImportRow row in rows) {
      final String accountId =
          _byName(accounts, row.account, (Account a) => a.name)?.id ??
          defaultAccountId;
      final String key = contentKey(accountId, row.date, row.type, row.amount);
      final String rowKey = '$key|${row.date.toIso8601String()}|${row.note}';
      final int n = seen[rowKey] = (seen[rowKey] ?? 0) + 1;
      final String id = _uuid.v5(
        Namespace.url.value,
        'import:$userId:$rowKey#$n',
      );
      final int matches = inApp[key] ?? 0;
      final String? imported = keyOfId[id];
      if (imported != null || matches > 0) {
        // Uses up one same-looking entry: the row's own earlier import if it
        // is unchanged, else another one. An edited import uses up none.
        if ((imported == null || imported == key) && matches > 0) {
          inApp[key] = matches - 1;
        }
        duplicates++;
        continue;
      }
      out.add(
        Transaction(
          id: id,
          userId: userId,
          accountId: accountId,
          categoryId: _category(categories, row)?.id,
          type: row.type,
          amount: row.amount,
          transactionDate: row.date,
          note: row.note.isEmpty ? null : row.note,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final Decimal signed = row.type == TransactionType.income
          ? row.amount
          : -row.amount;
      final ImportAccountChange? before = changes[accountId];
      changes[accountId] = ImportAccountChange(
        (before?.net ?? Decimal.zero) + signed,
        before == null || row.date.isBefore(before.earliest)
            ? row.date
            : before.earliest,
        (before?.count ?? 0) + 1,
      );
    }
    return ImportPlan(
      transactions: out,
      duplicates: duplicates,
      unreadable: unreadable,
      accounts: changes,
    );
  }

  /// The entry that keeps an account's balance where it was: it takes back
  /// [change]'s net, dated just before the earliest imported row, so the
  /// imported history starts from the right balance (docs/05: an opening
  /// balance is corrected by an entry, not rewritten). Null when the import
  /// does not move the balance.
  static Transaction? adjustment({
    required String accountId,
    required ImportAccountChange change,
    required String note,
    required String userId,
    required DateTime now,
  }) {
    if (change.net == Decimal.zero) return null;
    return Transaction(
      id: _uuid.v4(),
      userId: userId,
      accountId: accountId,
      type: change.net > Decimal.zero
          ? TransactionType.adjustment_out
          : TransactionType.adjustment_in,
      amount: change.net.abs(),
      transactionDate: change.earliest.subtract(const Duration(minutes: 1)),
      note: note,
      createdAt: now,
      updatedAt: now,
    );
  }

  static Category? _category(List<Category> categories, ImportRow row) {
    final CategoryType wanted = row.type == TransactionType.income
        ? CategoryType.income
        : CategoryType.expense;
    final List<Category> fitting = categories
        .where((Category c) => c.type == wanted || c.type == CategoryType.both)
        .toList();
    return _byName(fitting, row.category, (Category c) => c.name) ??
        _byName(
          fitting,
          row.type == TransactionType.income ? 'Other Income' : 'Other Expense',
          (Category c) => c.name,
        );
  }

  static T? _byName<T>(List<T> items, String name, String Function(T) nameOf) {
    final String wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final T item in items) {
      if (nameOf(item).trim().toLowerCase() == wanted) return item;
    }
    return null;
  }
}
