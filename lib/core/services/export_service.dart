import 'package:decimal/decimal.dart';
import 'package:excel/excel.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Formats supported for export.
enum ExportFormat { csv, excel, pdf }

/// Entity types that can be exported.
enum ExportType {
  transactions,
  accounts,
  contacts,
  contactTransactions,
  budgets,
  fullReport,
}

/// Pure Dart service to generate CSV, Excel (.xlsx), and PDF files
/// for transactions, accounts, contacts, khata entries, budgets, and full reports.
class ExportService {
  const ExportService();

  // ===========================================================================
  // CSV EXPORT
  // ===========================================================================

  /// Escapes CSV values according to RFC 4180:
  /// - Fields containing commas, double quotes, or line breaks are wrapped in double quotes.
  /// - Double quotes within a field are escaped by doubling them (`""`).
  static String escapeCsvValue(Object? value) {
    if (value == null) return '';
    final String str = value.toString();
    if (str.contains(',') ||
        str.contains('"') ||
        str.contains('\n') ||
        str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  /// Converts a matrix of rows into a valid CSV string with UTF-8 BOM.
  static String rowsToCsv(List<List<Object?>> rows) {
    final StringBuffer buffer = StringBuffer();
    // Prepend UTF-8 BOM so spreadsheet apps (Excel on Windows/Mac) auto-detect UTF-8.
    buffer.write('\uFEFF');
    for (final List<Object?> row in rows) {
      buffer.writeln(row.map(escapeCsvValue).join(','));
    }
    return buffer.toString();
  }

  /// Generates CSV for Transactions.
  String generateTransactionsCsv(
    List<Transaction> transactions, {
    Map<String, String>? accountNames,
    Map<String, String>? categoryNames,
  }) {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
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
      ],
    ];

    for (final Transaction tx in transactions) {
      final String accountName = accountNames?[tx.accountId] ?? tx.accountId;
      final String categoryName = tx.categoryId != null
          ? (categoryNames?[tx.categoryId] ?? tx.categoryId!)
          : '';
      final String dateStr = DateFormat(
        'yyyy-MM-dd',
      ).format(tx.transactionDate);
      final String timeStr = DateFormat('HH:mm:ss').format(tx.transactionDate);

      rows.add(<Object?>[
        tx.id,
        dateStr,
        timeStr,
        tx.type.name,
        accountName,
        categoryName,
        tx.amount.toDouble().toStringAsFixed(2),
        tx.paymentMethod ?? '',
        tx.note ?? '',
        tx.description ?? '',
      ]);
    }

    return rowsToCsv(rows);
  }

  /// Generates CSV for Accounts.
  String generateAccountsCsv(
    List<Account> accounts, {
    Map<String, Decimal>? currentBalances,
  }) {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'Account ID',
        'Name',
        'Type',
        'Opening Balance',
        'Current Balance',
        'Opening Date',
        'Active',
        'Created At',
      ],
    ];

    for (final Account acc in accounts) {
      final Decimal balance = currentBalances?[acc.id] ?? acc.openingBalance;
      rows.add(<Object?>[
        acc.id,
        acc.name,
        acc.type.name,
        acc.openingBalance.toDouble().toStringAsFixed(2),
        balance.toDouble().toStringAsFixed(2),
        acc.openingBalanceDate != null
            ? DateFormat('yyyy-MM-dd').format(acc.openingBalanceDate!)
            : '',
        acc.isActive ? 'Yes' : 'No',
        DateFormat('yyyy-MM-dd HH:mm').format(acc.createdAt),
      ]);
    }

    return rowsToCsv(rows);
  }

  /// Generates CSV for Contacts (Khata).
  String generateContactsCsv(
    List<Contact> contacts, {
    Map<String, Decimal>? netBalances,
  }) {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'Contact ID',
        'Name',
        'Phone',
        'Email',
        'Address',
        'Opening Balance',
        'Opening Type',
        'Current Net Balance',
        'Status',
        'Notes',
      ],
    ];

    for (final Contact c in contacts) {
      final Decimal net = netBalances?[c.id] ?? c.openingBalance;
      final String status = net > Decimal.zero
          ? "You'll Get"
          : (net < Decimal.zero ? "You'll Give" : 'Settled');

      rows.add(<Object?>[
        c.id,
        c.name,
        c.mobile ?? '',
        c.email ?? '',
        c.address ?? '',
        c.openingBalance.toDouble().toStringAsFixed(2),
        c.openingBalanceType,
        net.toDouble().toStringAsFixed(2),
        status,
        c.notes ?? '',
      ]);
    }

    return rowsToCsv(rows);
  }

  /// Generates CSV for Khata Transactions.
  String generateContactTransactionsCsv(
    List<ContactTransaction> transactions, {
    Map<String, String>? contactNames,
  }) {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'Transaction ID',
        'Contact Name',
        'Type',
        'Amount',
        'Date',
        'Due Date',
        'Note',
      ],
    ];

    for (final ContactTransaction tx in transactions) {
      final String contactName = contactNames?[tx.contactId] ?? tx.contactId;
      rows.add(<Object?>[
        tx.id,
        contactName,
        tx.type.name,
        tx.amount.toDouble().toStringAsFixed(2),
        DateFormat('yyyy-MM-dd').format(tx.transactionDate),
        tx.dueDate != null ? DateFormat('yyyy-MM-dd').format(tx.dueDate!) : '',
        tx.note ?? '',
      ]);
    }

    return rowsToCsv(rows);
  }

  /// Generates CSV for Budgets.
  String generateBudgetsCsv(
    List<Budget> budgets, {
    Map<String, String>? categoryNames,
  }) {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'Budget ID',
        'Category',
        'Limit Amount',
        'Period Type',
        'Start Date',
        'End Date',
        'Alert at 75%',
        'Alert at 90%',
        'Alert at 100%',
      ],
    ];

    for (final Budget b in budgets) {
      final String catName = b.categoryId != null
          ? (categoryNames?[b.categoryId] ?? b.categoryId!)
          : 'All Categories';
      rows.add(<Object?>[
        b.id,
        catName,
        b.amount.toDouble().toStringAsFixed(2),
        b.periodType.name,
        DateFormat('yyyy-MM-dd').format(b.startDate),
        b.endDate != null ? DateFormat('yyyy-MM-dd').format(b.endDate!) : '',
        b.alert75 ? 'Yes' : 'No',
        b.alert90 ? 'Yes' : 'No',
        b.alert100 ? 'Yes' : 'No',
      ]);
    }

    return rowsToCsv(rows);
  }

  // ===========================================================================
  // EXCEL (.xlsx) EXPORT
  // ===========================================================================

  /// Generates an Excel document for Transactions.
  List<int> generateTransactionsExcel(
    List<Transaction> transactions, {
    Map<String, String>? accountNames,
    Map<String, String>? categoryNames,
    String? currencyCode,
  }) {
    final Excel excel = Excel.createExcel();
    final Sheet sheet = excel['Transactions'];
    excel.setDefaultSheet('Transactions');
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Header styling
    final CellStyle headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1E88E5'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

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

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (int col = 0; col < headers.length; col++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
              .cellStyle =
          headerStyle;
    }

    double totalIncome = 0;
    double totalExpense = 0;

    for (final Transaction tx in transactions) {
      final String accountName = accountNames?[tx.accountId] ?? tx.accountId;
      final String categoryName = tx.categoryId != null
          ? (categoryNames?[tx.categoryId] ?? tx.categoryId!)
          : '';
      final String dateStr = DateFormat(
        'yyyy-MM-dd',
      ).format(tx.transactionDate);
      final String timeStr = DateFormat('HH:mm:ss').format(tx.transactionDate);
      final double amt = tx.amount.toDouble();

      if (tx.type == TransactionType.income ||
          tx.type == TransactionType.payment_received) {
        totalIncome += amt;
      } else if (tx.type == TransactionType.expense ||
          tx.type == TransactionType.payment_made) {
        totalExpense += amt;
      }

      sheet.appendRow(<CellValue>[
        TextCellValue(tx.id),
        TextCellValue(dateStr),
        TextCellValue(timeStr),
        TextCellValue(tx.type.name),
        TextCellValue(accountName),
        TextCellValue(categoryName),
        DoubleCellValue(amt),
        TextCellValue(tx.paymentMethod ?? ''),
        TextCellValue(tx.note ?? ''),
        TextCellValue(tx.description ?? ''),
      ]);
    }

    // Add empty row then Summary
    sheet.appendRow(<CellValue>[]);
    final int summaryRowIdx = sheet.maxRows;
    sheet.appendRow(<CellValue>[
      TextCellValue('SUMMARY'),
      TextCellValue('Total Transactions: ${transactions.length}'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Total Income:'),
      DoubleCellValue(totalIncome),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);
    sheet.appendRow(<CellValue>[
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Total Expense:'),
      DoubleCellValue(totalExpense),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);
    sheet.appendRow(<CellValue>[
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Net Savings:'),
      DoubleCellValue(totalIncome - totalExpense),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);

    final CellStyle summaryStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E0E0E0'),
    );
    for (int col = 0; col < headers.length; col++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(
                  columnIndex: col,
                  rowIndex: summaryRowIdx,
                ),
              )
              .cellStyle =
          summaryStyle;
    }

    return excel.encode() ?? <int>[];
  }

  /// Generates an Excel document for Accounts.
  List<int> generateAccountsExcel(
    List<Account> accounts, {
    Map<String, Decimal>? currentBalances,
  }) {
    final Excel excel = Excel.createExcel();
    final Sheet sheet = excel['Accounts'];
    excel.setDefaultSheet('Accounts');
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final CellStyle headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#2E7D32'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final List<String> headers = <String>[
      'Account ID',
      'Name',
      'Type',
      'Opening Balance',
      'Current Balance',
      'Opening Date',
      'Active',
      'Created At',
    ];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (int col = 0; col < headers.length; col++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
              .cellStyle =
          headerStyle;
    }

    double totalBalance = 0;

    for (final Account acc in accounts) {
      final Decimal balance = currentBalances?[acc.id] ?? acc.openingBalance;
      totalBalance += balance.toDouble();

      sheet.appendRow(<CellValue>[
        TextCellValue(acc.id),
        TextCellValue(acc.name),
        TextCellValue(acc.type.name),
        DoubleCellValue(acc.openingBalance.toDouble()),
        DoubleCellValue(balance.toDouble()),
        TextCellValue(
          acc.openingBalanceDate != null
              ? DateFormat('yyyy-MM-dd').format(acc.openingBalanceDate!)
              : '',
        ),
        TextCellValue(acc.isActive ? 'Yes' : 'No'),
        TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(acc.createdAt)),
      ]);
    }

    sheet.appendRow(<CellValue>[]);
    sheet.appendRow(<CellValue>[
      TextCellValue('Total Net Worth:'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(totalBalance),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);

    return excel.encode() ?? <int>[];
  }

  /// Generates full multi-sheet Excel report covering Transactions, Accounts, Khata, and Budgets.
  List<int> generateFullReportExcel({
    required List<Transaction> transactions,
    required List<Account> accounts,
    required List<Contact> contacts,
    required List<ContactTransaction> contactTransactions,
    required List<Budget> budgets,
    Map<String, String>? accountNames,
    Map<String, String>? categoryNames,
    Map<String, String>? contactNames,
    Map<String, Decimal>? accountBalances,
    Map<String, Decimal>? contactBalances,
  }) {
    final Excel excel = Excel.createExcel();

    // Sheet 1: Transactions
    final Sheet txSheet = excel['Transactions'];
    excel.setDefaultSheet('Transactions');
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    txSheet.appendRow(<CellValue>[
      TextCellValue('Transaction ID'),
      TextCellValue('Date'),
      TextCellValue('Type'),
      TextCellValue('Account'),
      TextCellValue('Category'),
      TextCellValue('Amount'),
      TextCellValue('Note'),
    ]);
    for (final Transaction tx in transactions) {
      txSheet.appendRow(<CellValue>[
        TextCellValue(tx.id),
        TextCellValue(DateFormat('yyyy-MM-dd').format(tx.transactionDate)),
        TextCellValue(tx.type.name),
        TextCellValue(accountNames?[tx.accountId] ?? tx.accountId),
        TextCellValue(
          tx.categoryId != null
              ? (categoryNames?[tx.categoryId] ?? tx.categoryId!)
              : '',
        ),
        DoubleCellValue(tx.amount.toDouble()),
        TextCellValue(tx.note ?? ''),
      ]);
    }

    // Sheet 2: Accounts
    final Sheet accSheet = excel['Accounts'];
    accSheet.appendRow(<CellValue>[
      TextCellValue('Name'),
      TextCellValue('Type'),
      TextCellValue('Opening Balance'),
      TextCellValue('Current Balance'),
      TextCellValue('Active'),
    ]);
    for (final Account a in accounts) {
      final Decimal bal = accountBalances?[a.id] ?? a.openingBalance;
      accSheet.appendRow(<CellValue>[
        TextCellValue(a.name),
        TextCellValue(a.type.name),
        DoubleCellValue(a.openingBalance.toDouble()),
        DoubleCellValue(bal.toDouble()),
        TextCellValue(a.isActive ? 'Yes' : 'No'),
      ]);
    }

    // Sheet 3: Khata Contacts
    final Sheet khataSheet = excel['Khata Contacts'];
    khataSheet.appendRow(<CellValue>[
      TextCellValue('Name'),
      TextCellValue('Phone'),
      TextCellValue('Opening Balance'),
      TextCellValue('Net Balance'),
      TextCellValue('Status'),
    ]);
    for (final Contact c in contacts) {
      final Decimal net = contactBalances?[c.id] ?? c.openingBalance;
      khataSheet.appendRow(<CellValue>[
        TextCellValue(c.name),
        TextCellValue(c.mobile ?? ''),
        DoubleCellValue(c.openingBalance.toDouble()),
        DoubleCellValue(net.toDouble()),
        TextCellValue(
          net > Decimal.zero
              ? "You'll Get"
              : (net < Decimal.zero ? "You'll Give" : 'Settled'),
        ),
      ]);
    }

    // Sheet 4: Budgets
    final Sheet budgetSheet = excel['Budgets'];
    budgetSheet.appendRow(<CellValue>[
      TextCellValue('Category'),
      TextCellValue('Amount Limit'),
      TextCellValue('Period Type'),
      TextCellValue('Start Date'),
      TextCellValue('End Date'),
    ]);
    for (final Budget b in budgets) {
      budgetSheet.appendRow(<CellValue>[
        TextCellValue(
          b.categoryId != null
              ? (categoryNames?[b.categoryId] ?? b.categoryId!)
              : 'All Categories',
        ),
        DoubleCellValue(b.amount.toDouble()),
        TextCellValue(b.periodType.name),
        TextCellValue(DateFormat('yyyy-MM-dd').format(b.startDate)),
        TextCellValue(
          b.endDate != null ? DateFormat('yyyy-MM-dd').format(b.endDate!) : '',
        ),
      ]);
    }

    return excel.encode() ?? <int>[];
  }

  // ===========================================================================
  // PDF REPORT EXPORT
  // ===========================================================================

  /// Generates a professional PDF report.
  Future<List<int>> generateReportPdf({
    required String title,
    required String periodLabel,
    required List<Transaction> transactions,
    Map<String, String>? accountNames,
    Map<String, String>? categoryNames,
    List<Contact>? contacts,
    Map<String, Decimal>? contactBalances,
    String? userName,
    String? userEmail,
    String currencyCode = 'INR',
  }) async {
    final pw.Document doc = pw.Document();

    // Calculate totals
    double totalIncome = 0;
    double totalExpense = 0;
    final Map<String, double> categoryTotals = <String, double>{};

    for (final Transaction tx in transactions) {
      final double amt = tx.amount.toDouble();
      if (tx.type == TransactionType.income ||
          tx.type == TransactionType.payment_received) {
        totalIncome += amt;
      } else if (tx.type == TransactionType.expense ||
          tx.type == TransactionType.payment_made) {
        totalExpense += amt;
        final String catName = tx.categoryId != null
            ? (categoryNames?[tx.categoryId] ?? 'Category')
            : 'Uncategorized';
        categoryTotals[catName] = (categoryTotals[catName] ?? 0) + amt;
      }
    }
    final double netSavings = totalIncome - totalExpense;

    // Format currency cleanly without unicode symbol issues in PDF standard fonts
    String fmtMoney(double value) {
      final String prefix = value < 0 ? '-' : '';
      return '$prefix$currencyCode ${value.abs().toStringAsFixed(2)}';
    }

    final PdfColor primaryColor = PdfColor.fromHex('#1E88E5');
    final PdfColor incomeColor = PdfColor.fromHex('#2E7D32');
    final PdfColor expenseColor = PdfColor.fromHex('#C62828');
    final PdfColor textDark = PdfColor.fromHex('#212121');
    final PdfColor textMuted = PdfColor.fromHex('#757575');
    final PdfColor cardBg = PdfColor.fromHex('#F5F5F5');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            margin: const pw.EdgeInsets.only(bottom: 16),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 1),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      'FINANCE TRACKER',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    pw.Text(
                      title,
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: <pw.Widget>[
                    pw.Text(
                      'Period: $periodLabel',
                      style: pw.TextStyle(fontSize: 10, color: textMuted),
                    ),
                    pw.Text(
                      'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 9, color: textMuted),
                    ),
                    if (userName != null && userName.isNotEmpty)
                      pw.Text(
                        'User: $userName',
                        style: pw.TextStyle(fontSize: 9, color: textMuted),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 10),
            margin: const pw.EdgeInsets.only(top: 16),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                pw.Text(
                  'Confidential - Personal Financial Report',
                  style: pw.TextStyle(fontSize: 8, color: textMuted),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: textMuted),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return <pw.Widget>[
            // Summary KPI Cards
            pw.Row(
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: cardBg,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Text(
                          'TOTAL INCOME',
                          style: pw.TextStyle(fontSize: 9, color: textMuted),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          fmtMoney(totalIncome),
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: incomeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: cardBg,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Text(
                          'TOTAL EXPENSE',
                          style: pw.TextStyle(fontSize: 9, color: textMuted),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          fmtMoney(totalExpense),
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: expenseColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: cardBg,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Text(
                          'NET SAVINGS',
                          style: pw.TextStyle(fontSize: 9, color: textMuted),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          fmtMoney(netSavings),
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: netSavings >= 0
                                ? primaryColor
                                : expenseColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Top Expense Categories (if any)
            if (categoryTotals.isNotEmpty) ...<pw.Widget>[
              pw.Text(
                'Expense Breakdown by Category',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: textDark,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                border: null,
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                headers: <String>['Category', 'Amount', '% of Total Expense'],
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                  ),
                ),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellPadding: const pw.EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                data: categoryTotals.entries.map((entry) {
                  final double pct = totalExpense > 0
                      ? (entry.value / totalExpense * 100)
                      : 0;
                  return <String>[
                    entry.key,
                    fmtMoney(entry.value),
                    '${pct.toStringAsFixed(1)}%',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 20),
            ],

            // Khata Details Summary (if provided)
            if (contacts != null && contacts.isNotEmpty) ...<pw.Widget>[
              pw.Text(
                'Khata Contacts Summary',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: textDark,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                border: null,
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                headers: <String>['Contact', 'Phone', 'Net Balance', 'Status'],
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                  ),
                ),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellPadding: const pw.EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                data: contacts.map((c) {
                  final Decimal net =
                      contactBalances?[c.id] ?? c.openingBalance;
                  final String status = net > Decimal.zero
                      ? "You'll Get"
                      : (net < Decimal.zero ? "You'll Give" : 'Settled');
                  return <String>[
                    c.name,
                    c.mobile ?? '-',
                    fmtMoney(net.toDouble()),
                    status,
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 20),
            ],

            // Detailed Transactions Table
            pw.Text(
              'Transactions (${transactions.length})',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: textDark,
              ),
            ),
            pw.SizedBox(height: 8),
            if (transactions.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'No transactions found for the selected period.',
                  style: pw.TextStyle(fontSize: 9, color: textMuted),
                ),
              )
            else
              pw.TableHelper.fromTextArray(
                border: null,
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                headers: <String>[
                  'Date',
                  'Account',
                  'Category',
                  'Type',
                  'Note',
                  'Amount',
                ],
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                  ),
                ),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellPadding: const pw.EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 6,
                ),
                data: transactions.map((tx) {
                  final String accName =
                      accountNames?[tx.accountId] ?? tx.accountId;
                  final String catName = tx.categoryId != null
                      ? (categoryNames?[tx.categoryId] ?? tx.categoryId!)
                      : '-';
                  final String dateStr = DateFormat(
                    'yyyy-MM-dd',
                  ).format(tx.transactionDate);
                  final double amt = tx.amount.toDouble();
                  final bool isPositive =
                      tx.type == TransactionType.income ||
                      tx.type == TransactionType.payment_received;
                  return <String>[
                    dateStr,
                    accName,
                    catName,
                    tx.type.name,
                    tx.note ?? tx.description ?? '',
                    '${isPositive ? '+' : '-'}${fmtMoney(amt)}',
                  ];
                }).toList(),
              ),
          ];
        },
      ),
    );

    return doc.save();
  }
}
