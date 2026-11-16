import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/external_activity.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/statement_import.dart';
import 'package:finance_tracker/features/import/services/import_file_reader.dart';
import 'package:flutter/foundation.dart' show Uint8List, compute;
import 'package:get/get.dart';

/// Import screen state: the chosen file, which column holds what, and the
/// plan StatementImport makes from them. Every import keeps each account's
/// balance unless the user lets it change (an adjustment entry per account).
class ImportController extends GetxController {
  ImportController(
    this._transactions,
    this._accounts,
    this._categories,
    this._auth,
    this._notifier, {
    Future<({String name, Uint8List bytes})?> Function()? pickFile,
  }) : _pick = pickFile ?? _pickFromDevice;

  final TransactionRepository _transactions;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final AuthRepository _auth;
  final DataChangeNotifier _notifier;
  final Future<({String name, Uint8List bytes})?> Function() _pick;

  final RxBool isLoading = true.obs;
  final RxnString loadError = RxnString();
  final RxList<Account> accounts = <Account>[].obs;

  final RxBool isReading = false.obs;
  final RxnString fileError = RxnString();
  final RxnString fileName = RxnString();
  final Rxn<ImportTable> table = Rxn<ImportTable>();
  final RxMap<ImportField, int> columns = <ImportField, int>{}.obs;

  /// For rows without an account column, or with an account not in the app.
  final RxnString accountId = RxnString();

  /// Accounts whose balance the user lets the import change; the others get
  /// an adjustment entry.
  final RxSet<String> balanceChanges = <String>{}.obs;
  final Rxn<ImportPlan> plan = Rxn<ImportPlan>();
  final SubmitState save = SubmitState();

  List<Category> _categoryList = const <Category>[];
  List<Transaction> _existing = const <Transaction>[];
  Map<String, Decimal> _balances = const <String, Decimal>{};

  static Future<({String name, Uint8List bytes})?> _pickFromDevice() async {
    final PlatformFile? file = await ExternalActivity.run(
      () => FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['csv', 'xlsx', 'xls'],
      ),
    );
    if (file == null) return null;
    return (name: file.xFile.name, bytes: await file.xFile.readAsBytes());
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    loadError.value = null;
    try {
      final (
        List<Account> all,
        List<Category> categories,
        List<Transaction> existing,
      ) = await wait3(
        _accounts.getAccounts(),
        _categories.getCategories(),
        _transactions.getAllTransactions(),
      );
      final List<Account> active = all
          .where((Account a) => a.isActive)
          .toList();
      accounts.assignAll(active);
      _categoryList = categories;
      _existing = existing;
      _balances = FinanceSummaryCalculator.accountBalances(active, existing);
      if (accountId.value == null && active.isNotEmpty) {
        accountId.value = active.first.id;
      }
      _replan();
    } on AppException catch (failure) {
      loadError.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> chooseFile() async {
    if (isReading.value) return;
    fileError.value = null;
    isReading.value = true;
    try {
      final ({String name, Uint8List bytes})? file = await _pick();
      if (file == null) return;
      final List<List<String>> raw = await compute(readImportFile, file);
      final ImportTable? found = StatementImport.table(raw);
      if (found == null || found.rows.isEmpty) {
        fileError.value = 'No rows found in this file.'.tr;
        return;
      }
      fileName.value = file.name;
      table.value = found;
      columns.assignAll(StatementImport.guessColumns(found.headers));
      balanceChanges.clear();
      _replan();
    } on ImportFileException catch (failure) {
      fileError.value = failure.message.tr;
    } on Object catch (error) {
      developer.log('Not read: ${error.runtimeType}', name: 'import');
      fileError.value =
          'This file could not be read. Choose a CSV or Excel (.xlsx) file.'.tr;
    } finally {
      isReading.value = false;
    }
  }

  bool get hasRequiredColumns => StatementImport.hasMoneyAndDate(columns);

  /// One column per field. Amount and Debit/Credit are two ways to read the
  /// money, so choosing one clears the other.
  void setColumn(ImportField field, int? index) {
    if (index == null) {
      columns.remove(field);
    } else {
      columns.removeWhere((ImportField f, int i) => i == index);
      if (field == ImportField.amount) {
        columns
          ..remove(ImportField.debit)
          ..remove(ImportField.credit);
      } else if (field == ImportField.debit || field == ImportField.credit) {
        columns.remove(ImportField.amount);
      }
      columns[field] = index;
    }
    _replan();
  }

  void setAccount(String? id) {
    accountId.value = id;
    _replan();
  }

  void setKeepBalance(String accountId, {required bool keep}) =>
      keep ? balanceChanges.remove(accountId) : balanceChanges.add(accountId);

  Decimal balanceOf(String accountId) => _balances[accountId] ?? Decimal.zero;

  String accountName(String id) =>
      accounts.firstWhereOrNull((Account a) => a.id == id)?.name ?? '';

  Category? categoryOf(String? id) =>
      _categoryList.firstWhereOrNull((Category c) => c.id == id);

  void _replan() {
    final ImportTable? file = table.value;
    final String? account = accountId.value;
    final String? userId = _auth.currentUserId;
    if (file == null || account == null || userId == null) {
      plan.value = null;
      return;
    }
    if (!hasRequiredColumns) {
      plan.value = null;
      return;
    }
    final ({List<ImportRow> rows, int unreadable}) read = StatementImport.read(
      file,
      columns,
    );
    plan.value = StatementImport.plan(
      rows: read.rows,
      unreadable: read.unreadable,
      accounts: accounts,
      categories: _categoryList,
      existing: _existing,
      defaultAccountId: account,
      userId: userId,
      now: DateTime.now(),
    );
  }

  /// Saves the plan, with an adjustment for every account whose balance is
  /// kept. Returns true when it was saved.
  Future<bool> importNow() async {
    final ImportPlan? current = plan.value;
    final String? userId = _auth.currentUserId;
    if (current == null || userId == null || current.transactions.isEmpty) {
      return false;
    }
    final DateTime now = DateTime.now();
    return save.run(() async {
      final List<Transaction> rows = <Transaction>[
        ...current.transactions,
        for (final MapEntry<String, ImportAccountChange> change
            in current.accounts.entries)
          if (!balanceChanges.contains(change.key))
            ?StatementImport.adjustment(
              accountId: change.key,
              change: change.value,
              note: 'Import adjustment'.tr,
              userId: userId,
              now: now,
            ),
      ];
      try {
        await _transactions.importTransactions(rows);
      } on AppException {
        rethrow;
      } on Object catch (error) {
        developer.log('Not saved: ${error.runtimeType}', name: 'import');
        throw const DatabaseFailure();
      }
      _notifier.markChanged();
    });
  }
}
