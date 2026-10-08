import 'dart:async';
import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/export_service.dart';
import 'package:finance_tracker/core/services/file_sharing_service.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/budget_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

enum DateRangePreset {
  all('All Time'),
  today('Today'),
  thisWeek('This Week'),
  thisMonth('This Month'),
  lastMonth('Last Month'),
  last3Months('Last 3 Months'),
  custom('Custom Range');

  const DateRangePreset(this.label);
  final String label;
}

class ExportController extends GetxController {
  ExportController({
    required this.transactionRepository,
    required this.accountRepository,
    required this.contactRepository,
    required this.budgetRepository,
    required this.categoryRepository,
    this.authRepository,
    this.profileRepository,
    this.exportService = const ExportService(),
    this.sharingService = const FileSharingService(),
  });

  final TransactionRepository transactionRepository;
  final AccountRepository accountRepository;
  final ContactRepository contactRepository;
  final BudgetRepository budgetRepository;
  final CategoryRepository categoryRepository;
  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final ExportService exportService;
  final FileSharingService sharingService;

  // Selected scope & format
  final Rx<ExportType> selectedType = ExportType.transactions.obs;
  final Rx<ExportFormat> selectedFormat = ExportFormat.csv.obs;

  // Filters
  final Rx<DateRangePreset> datePreset = DateRangePreset.thisMonth.obs;
  final Rxn<DateTime> customStartDate = Rxn<DateTime>();
  final Rxn<DateTime> customEndDate = Rxn<DateTime>();
  final Rxn<String> selectedAccountId = Rxn<String>();
  final Rxn<String> selectedCategoryId = Rxn<String>();
  final Rxn<TransactionType> selectedTxType = Rxn<TransactionType>();

  // Available options
  final RxList<Account> accounts = <Account>[].obs;
  final RxList<Category> categories = <Category>[].obs;

  // Status
  final RxBool isLoadingOptions = false.obs;
  final RxBool isExporting = false.obs;
  final RxString statusMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _loadFilterOptions();
  }

  Future<void> _loadFilterOptions() async {
    isLoadingOptions.value = true;
    try {
      final List<Account> accs = await accountRepository.getAccounts();
      final List<Category> cats = await categoryRepository.getCategories();
      accounts.assignAll(accs);
      categories.assignAll(cats);
    } catch (e) {
      debugPrint('Error loading export filter options: $e');
    } finally {
      isLoadingOptions.value = false;
    }
  }

  ({DateTime? start, DateTime? end}) get activeDateRange {
    final DateTime now = DateTime.now();
    switch (datePreset.value) {
      case DateRangePreset.all:
        return (start: null, end: null);
      case DateRangePreset.today:
        final DateTime todayStart = DateTime(now.year, now.month, now.day);
        final DateTime todayEnd = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        );
        return (start: todayStart, end: todayEnd);
      case DateRangePreset.thisWeek:
        final int weekday = now.weekday; // 1 = Monday
        final DateTime startOfWeek = DateTime(
          now.year,
          now.month,
          now.day - (weekday - 1),
        );
        final DateTime endOfWeek = DateTime(
          now.year,
          now.month,
          now.day + (7 - weekday),
          23,
          59,
          59,
        );
        return (start: startOfWeek, end: endOfWeek);
      case DateRangePreset.thisMonth:
        final DateTime startOfMonth = DateTime(now.year, now.month, 1);
        final DateTime endOfMonth = DateTime(
          now.year,
          now.month + 1,
          0,
          23,
          59,
          59,
        );
        return (start: startOfMonth, end: endOfMonth);
      case DateRangePreset.lastMonth:
        final DateTime startOfLastMonth = DateTime(now.year, now.month - 1, 1);
        final DateTime endOfLastMonth = DateTime(
          now.year,
          now.month,
          0,
          23,
          59,
          59,
        );
        return (start: startOfLastMonth, end: endOfLastMonth);
      case DateRangePreset.last3Months:
        final DateTime start = DateTime(now.year, now.month - 2, 1);
        final DateTime end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return (start: start, end: end);
      case DateRangePreset.custom:
        return (
          start: customStartDate.value,
          end: customEndDate.value != null
              ? DateTime(
                  customEndDate.value!.year,
                  customEndDate.value!.month,
                  customEndDate.value!.day,
                  23,
                  59,
                  59,
                )
              : null,
        );
    }
  }

  String get dateRangeLabel {
    final ({DateTime? start, DateTime? end}) range = activeDateRange;
    if (range.start == null && range.end == null) return 'All Time';
    if (range.start != null && range.end != null) {
      final DateFormat df = DateFormat('MMM dd, yyyy');
      return '${df.format(range.start!)} - ${df.format(range.end!)}';
    }
    return datePreset.value.label;
  }

  void setCustomRange(DateTime start, DateTime end) {
    customStartDate.value = start;
    customEndDate.value = end;
    datePreset.value = DateRangePreset.custom;
  }

  Future<void> exportAndShare() async {
    if (isExporting.value) return;
    isExporting.value = true;
    statusMessage.value = 'Preparing data for export...';

    try {
      final Map<String, String> accountNames = <String, String>{
        for (final Account a in accounts) a.id: a.name,
      };
      final Map<String, String> categoryNames = <String, String>{
        for (final Category c in categories) c.id: c.name,
      };

      final String timeStamp = DateFormat(
        'yyyyMMdd_HHmmss',
      ).format(DateTime.now());

      switch (selectedType.value) {
        case ExportType.transactions:
          await _exportTransactions(timeStamp, accountNames, categoryNames);
          break;
        case ExportType.accounts:
          await _exportAccounts(timeStamp);
          break;
        case ExportType.contacts:
          await _exportContacts(timeStamp);
          break;
        case ExportType.contactTransactions:
          await _exportContactTransactions(timeStamp);
          break;
        case ExportType.budgets:
          await _exportBudgets(timeStamp, categoryNames);
          break;
        case ExportType.fullReport:
          await _exportFullReport(timeStamp, accountNames, categoryNames);
          break;
      }
    } catch (e, stack) {
      debugPrint('Export error: $e\n$stack');
      AppSnackbar.show(
        'Export failed: ${e.toString().replaceAll('Exception: ', '')}',
      );
    } finally {
      isExporting.value = false;
      statusMessage.value = '';
    }
  }

  Future<void> _exportTransactions(
    String timeStamp,
    Map<String, String> accountNames,
    Map<String, String> categoryNames,
  ) async {
    final ({DateTime? start, DateTime? end}) range = activeDateRange;
    final List<Transaction> txs = await transactionRepository.getTransactions(
      accountId: selectedAccountId.value,
      categoryId: selectedCategoryId.value,
      type: selectedTxType.value,
      startDate: range.start,
      endDate: range.end,
      limit: 100000,
    );

    if (txs.isEmpty) {
      AppSnackbar.show('No transactions match the selected filters.');
      return;
    }

    statusMessage.value =
        'Generating document for ${txs.length} transactions...';

    if (selectedFormat.value == ExportFormat.csv) {
      final String csv = await compute(
        _computeTransactionsCsv,
        _TxCsvArgs(txs, accountNames, categoryNames),
      );
      await sharingService.saveAndShareString(
        fileName: 'transactions_$timeStamp.csv',
        content: csv,
        mimeType: 'text/csv',
        subject: 'Finance Tracker Transactions Export',
      );
    } else if (selectedFormat.value == ExportFormat.excel) {
      final List<int> bytes = await compute(
        _computeTransactionsExcel,
        _TxExcelArgs(txs, accountNames, categoryNames),
      );
      await sharingService.saveAndShareBytes(
        fileName: 'transactions_$timeStamp.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: 'Finance Tracker Transactions Spreadsheet',
      );
    } else {
      // PDF Report
      Profile? profile;
      if (profileRepository != null) {
        try {
          profile = await profileRepository!.fetchProfile();
        } catch (_) {}
      }
      final List<int> pdfBytes = await exportService.generateReportPdf(
        title: 'Transactions Report',
        periodLabel: dateRangeLabel,
        transactions: txs,
        accountNames: accountNames,
        categoryNames: categoryNames,
        userName: profile?.fullName ?? authRepository?.currentEmail,
        currencyCode:
            profile?.currencyCode ?? AppFormatters.preferences.currencyCode,
      );
      await sharingService.saveAndShareBytes(
        fileName: 'transactions_report_$timeStamp.pdf',
        bytes: pdfBytes,
        mimeType: 'application/pdf',
        subject: 'Finance Tracker Transactions Report',
      );
    }

    AppSnackbar.show('Export ready!');
  }

  Future<void> _exportAccounts(String timeStamp) async {
    final List<Account> accs = await accountRepository.getAccounts();
    if (accs.isEmpty) {
      AppSnackbar.show('No accounts found to export.');
      return;
    }

    statusMessage.value = 'Generating accounts export...';

    if (selectedFormat.value == ExportFormat.csv) {
      final String csv = exportService.generateAccountsCsv(accs);
      await sharingService.saveAndShareString(
        fileName: 'accounts_$timeStamp.csv',
        content: csv,
        mimeType: 'text/csv',
        subject: 'Accounts Export',
      );
    } else if (selectedFormat.value == ExportFormat.excel) {
      final List<int> bytes = exportService.generateAccountsExcel(accs);
      await sharingService.saveAndShareBytes(
        fileName: 'accounts_$timeStamp.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: 'Accounts Spreadsheet',
      );
    } else {
      // PDF for accounts
      final List<Transaction> allTxs = await transactionRepository
          .getAllTransactions();
      final List<int> pdfBytes = await exportService.generateReportPdf(
        title: 'Accounts Statement',
        periodLabel: 'All Active Accounts',
        transactions: allTxs.take(100).toList(),
        accountNames: <String, String>{
          for (final Account a in accs) a.id: a.name,
        },
      );
      await sharingService.saveAndShareBytes(
        fileName: 'accounts_statement_$timeStamp.pdf',
        bytes: pdfBytes,
        mimeType: 'application/pdf',
        subject: 'Accounts Statement',
      );
    }

    AppSnackbar.show('Accounts export ready!');
  }

  Future<void> _exportContacts(String timeStamp) async {
    final List<Contact> contacts = await contactRepository.getContacts();
    if (contacts.isEmpty) {
      AppSnackbar.show('No khata contacts found to export.');
      return;
    }

    statusMessage.value = 'Generating khata contacts export...';

    // Calculate balances
    final Map<String, Decimal> netBalances = <String, Decimal>{};
    for (final Contact c in contacts) {
      final List<ContactTransaction> txs = await contactRepository
          .getContactTransactions(c.id);
      netBalances[c.id] = c.getCurrentBalance(txs);
    }

    if (selectedFormat.value == ExportFormat.csv) {
      final String csv = exportService.generateContactsCsv(
        contacts,
        netBalances: netBalances,
      );
      await sharingService.saveAndShareString(
        fileName: 'khata_contacts_$timeStamp.csv',
        content: csv,
        mimeType: 'text/csv',
        subject: 'Khata Contacts Export',
      );
    } else if (selectedFormat.value == ExportFormat.excel) {
      final List<int> bytes = exportService.generateFullReportExcel(
        transactions: <Transaction>[],
        accounts: <Account>[],
        contacts: contacts,
        contactTransactions: <ContactTransaction>[],
        budgets: <Budget>[],
        contactBalances: netBalances,
      );
      await sharingService.saveAndShareBytes(
        fileName: 'khata_contacts_$timeStamp.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: 'Khata Contacts Spreadsheet',
      );
    } else {
      final List<int> pdfBytes = await exportService.generateReportPdf(
        title: 'Khata Contacts Report',
        periodLabel: 'Digital Khata Summary',
        transactions: <Transaction>[],
        contacts: contacts,
        contactBalances: netBalances,
      );
      await sharingService.saveAndShareBytes(
        fileName: 'khata_report_$timeStamp.pdf',
        bytes: pdfBytes,
        mimeType: 'application/pdf',
        subject: 'Khata Contacts Report',
      );
    }

    AppSnackbar.show('Khata export ready!');
  }

  Future<void> _exportContactTransactions(String timeStamp) async {
    final List<ContactTransaction> txs = await contactRepository
        .getAllContactTransactions();
    if (txs.isEmpty) {
      AppSnackbar.show('No khata transactions found to export.');
      return;
    }

    final List<Contact> contacts = await contactRepository.getContacts();
    final Map<String, String> contactNames = <String, String>{
      for (final Contact c in contacts) c.id: c.name,
    };

    if (selectedFormat.value == ExportFormat.csv) {
      final String csv = exportService.generateContactTransactionsCsv(
        txs,
        contactNames: contactNames,
      );
      await sharingService.saveAndShareString(
        fileName: 'khata_transactions_$timeStamp.csv',
        content: csv,
        mimeType: 'text/csv',
        subject: 'Khata Transactions Export',
      );
    } else {
      final List<int> bytes = exportService.generateFullReportExcel(
        transactions: <Transaction>[],
        accounts: <Account>[],
        contacts: contacts,
        contactTransactions: txs,
        budgets: <Budget>[],
        contactNames: contactNames,
      );
      await sharingService.saveAndShareBytes(
        fileName: 'khata_transactions_$timeStamp.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: 'Khata Transactions Spreadsheet',
      );
    }

    AppSnackbar.show('Khata transactions export ready!');
  }

  Future<void> _exportBudgets(
    String timeStamp,
    Map<String, String> categoryNames,
  ) async {
    final List<Budget> budgets = await budgetRepository.getBudgets();
    if (budgets.isEmpty) {
      AppSnackbar.show('No budgets found to export.');
      return;
    }

    if (selectedFormat.value == ExportFormat.csv) {
      final String csv = exportService.generateBudgetsCsv(
        budgets,
        categoryNames: categoryNames,
      );
      await sharingService.saveAndShareString(
        fileName: 'budgets_$timeStamp.csv',
        content: csv,
        mimeType: 'text/csv',
        subject: 'Budgets Export',
      );
    } else {
      final List<int> bytes = exportService.generateFullReportExcel(
        transactions: <Transaction>[],
        accounts: <Account>[],
        contacts: <Contact>[],
        contactTransactions: <ContactTransaction>[],
        budgets: budgets,
        categoryNames: categoryNames,
      );
      await sharingService.saveAndShareBytes(
        fileName: 'budgets_$timeStamp.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: 'Budgets Spreadsheet',
      );
    }

    AppSnackbar.show('Budgets export ready!');
  }

  Future<void> _exportFullReport(
    String timeStamp,
    Map<String, String> accountNames,
    Map<String, String> categoryNames,
  ) async {
    statusMessage.value = 'Compiling full financial report...';
    final ({DateTime? start, DateTime? end}) range = activeDateRange;

    final List<Transaction> txs = await transactionRepository.getTransactions(
      startDate: range.start,
      endDate: range.end,
      limit: 100000,
    );
    final List<Account> accs = await accountRepository.getAccounts();
    final List<Contact> contacts = await contactRepository.getContacts();
    final List<ContactTransaction> contactTxs = await contactRepository
        .getAllContactTransactions();
    final List<Budget> budgets = await budgetRepository.getBudgets();

    final Map<String, String> contactNames = <String, String>{
      for (final Contact c in contacts) c.id: c.name,
    };

    if (selectedFormat.value == ExportFormat.pdf) {
      Profile? profile;
      if (profileRepository != null) {
        try {
          profile = await profileRepository!.fetchProfile();
        } catch (_) {}
      }

      final List<int> pdfBytes = await exportService.generateReportPdf(
        title: 'Comprehensive Financial Report',
        periodLabel: dateRangeLabel,
        transactions: txs,
        accountNames: accountNames,
        categoryNames: categoryNames,
        contacts: contacts,
        userName: profile?.fullName ?? authRepository?.currentEmail,
        currencyCode:
            profile?.currencyCode ?? AppFormatters.preferences.currencyCode,
      );

      await sharingService.saveAndShareBytes(
        fileName: 'full_financial_report_$timeStamp.pdf',
        bytes: pdfBytes,
        mimeType: 'application/pdf',
        subject: 'Full Financial Report',
      );
    } else {
      // Excel multi-sheet is best for full multi-entity report
      final List<int> bytes = exportService.generateFullReportExcel(
        transactions: txs,
        accounts: accs,
        contacts: contacts,
        contactTransactions: contactTxs,
        budgets: budgets,
        accountNames: accountNames,
        categoryNames: categoryNames,
        contactNames: contactNames,
      );

      await sharingService.saveAndShareBytes(
        fileName: 'full_financial_workbook_$timeStamp.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: 'Full Financial Workbook',
      );
    }

    AppSnackbar.show('Full report ready!');
  }
}

// Compute Helpers for background processing
class _TxCsvArgs {
  const _TxCsvArgs(this.transactions, this.accountNames, this.categoryNames);
  final List<Transaction> transactions;
  final Map<String, String> accountNames;
  final Map<String, String> categoryNames;
}

String _computeTransactionsCsv(_TxCsvArgs args) {
  const ExportService service = ExportService();
  return service.generateTransactionsCsv(
    args.transactions,
    accountNames: args.accountNames,
    categoryNames: args.categoryNames,
  );
}

class _TxExcelArgs {
  const _TxExcelArgs(this.transactions, this.accountNames, this.categoryNames);
  final List<Transaction> transactions;
  final Map<String, String> accountNames;
  final Map<String, String> categoryNames;
}

List<int> _computeTransactionsExcel(_TxExcelArgs args) {
  const ExportService service = ExportService();
  return service.generateTransactionsExcel(
    args.transactions,
    accountNames: args.accountNames,
    categoryNames: args.categoryNames,
  );
}
