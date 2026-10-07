import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// Arguments for the transaction form route. [existing] switches it to edit
/// mode; otherwise [type] picks income or expense.
class TransactionFormArgs {
  const TransactionFormArgs({
    this.type = TransactionType.expense,
    this.existing,
  });

  final TransactionType type;
  final Transaction? existing;
}

/// List, search, filter, create, edit and delete for income/expense records.
class TransactionController extends GetxController {
  TransactionController(
    this._transactionRepository,
    this._accountRepository,
    this._categoryRepository,
    this._notifier,
  );

  final TransactionRepository _transactionRepository;
  final AccountRepository _accountRepository;
  final CategoryRepository _categoryRepository;
  final DataChangeNotifier _notifier;

  static const int pageSize = 30;
  static const Uuid _uuid = Uuid();

  final RxList<Transaction> items = <Transaction>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxnString error = RxnString();

  // Filters.
  final RxString searchText = ''.obs;
  final Rxn<TransactionType> typeFilter = Rxn<TransactionType>();
  final RxnString accountFilter = RxnString();
  final RxnString categoryFilter = RxnString();
  final Rxn<DateTimeRange> rangeFilter = Rxn<DateTimeRange>();

  // Lookups for tiles and the form.
  final RxList<Account> accounts = <Account>[].obs;
  final RxList<Category> categories = <Category>[].obs;
  final RxnString lookupError = RxnString();
  final RxBool lookupsLoaded = false.obs;

  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();

  int _generation = 0;

  bool get hasActiveFilters =>
      typeFilter.value != null ||
      accountFilter.value != null ||
      categoryFilter.value != null ||
      rangeFilter.value != null;

  @override
  void onInit() {
    super.onInit();
    loadLookups();
    load();
    debounce<String>(
      searchText,
      (_) => load(),
      time: const Duration(milliseconds: 400),
    );
    ever<int>(_notifier.version, (_) {
      loadLookups();
      load(silent: true);
    });
  }

  Future<void> loadLookups() async {
    try {
      final (List<Account> a, List<Category> c) = await wait2(
        _accountRepository.getAccounts(),
        _categoryRepository.getCategories(),
      );
      accounts.assignAll(a.where((Account x) => x.isActive));
      categories.assignAll(c);
      lookupError.value = null;
    } on AppException catch (failure) {
      lookupError.value = failure.message;
    } finally {
      lookupsLoaded.value = true;
    }
  }

  Category? categoryOf(String? id) {
    if (id == null) return null;
    for (final Category c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String accountName(String id) {
    for (final Account a in accounts) {
      if (a.id == id) return a.name;
    }
    return 'Account';
  }

  /// Categories usable for [type] (income, expense or both).
  List<Category> categoriesFor(TransactionType type) => categories
      .where(
        (Category c) =>
            c.type == CategoryType.both ||
            (type == TransactionType.income
                ? c.type == CategoryType.income
                : c.type == CategoryType.expense),
      )
      .toList();

  Future<List<Transaction>> _fetch(int offset) =>
      _transactionRepository.getTransactions(
        type: typeFilter.value,
        accountId: accountFilter.value,
        categoryId: categoryFilter.value,
        search: searchText.value,
        startDate: rangeFilter.value?.start,
        endDate: rangeFilter.value == null
            ? null
            : DateTime(
                rangeFilter.value!.end.year,
                rangeFilter.value!.end.month,
                rangeFilter.value!.end.day,
                23,
                59,
                59,
              ),
        limit: pageSize,
        offset: offset,
      );

  /// Reloads from the first page. A [silent] reload keeps the list visible.
  Future<void> load({bool silent = false}) async {
    final int generation = ++_generation;
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final List<Transaction> page = await _fetch(0);
      if (generation != _generation) return;
      items.assignAll(page);
      hasMore.value = page.length == pageSize;
    } on AppException catch (failure) {
      if (generation == _generation) error.value = failure.message;
    } finally {
      if (generation == _generation) isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoading.value || isLoadingMore.value || !hasMore.value) return;
    final int generation = _generation;
    isLoadingMore.value = true;
    try {
      final List<Transaction> page = await _fetch(items.length);
      if (generation != _generation) return;
      items.addAll(page);
      hasMore.value = page.length == pageSize;
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      isLoadingMore.value = false;
    }
  }

  void applyFilters({
    TransactionType? type,
    String? accountId,
    String? categoryId,
    DateTimeRange? range,
  }) {
    typeFilter.value = type;
    accountFilter.value = accountId;
    categoryFilter.value = categoryId;
    rangeFilter.value = range;
    load();
  }

  void clearFilters() => applyFilters();

  /// Creates or updates a transaction. The id is generated once per form
  /// ([id]) so a retried save upserts the same row instead of duplicating it.
  Future<bool> saveTransaction({
    required String id,
    Transaction? existing,
    required TransactionType type,
    required Decimal amount,
    required String accountId,
    required String? categoryId,
    required DateTime date,
    required String? note,
  }) {
    return save.run(() async {
      final DateTime now = DateTime.now();
      final Transaction transaction = Transaction(
        id: id,
        userId: existing?.userId ?? '',
        accountId: accountId,
        categoryId: categoryId,
        contactId: existing?.contactId,
        type: type,
        amount: amount,
        transactionDate: date,
        note: note,
        description: existing?.description,
        paymentMethod: existing?.paymentMethod,
        transferId: existing?.transferId,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      if (existing == null) {
        await _transactionRepository.createTransaction(transaction);
      } else {
        await _transactionRepository.updateTransaction(transaction);
      }
      _notifier.markChanged();
    });
  }

  Future<bool> deleteTransaction(String transactionId) {
    return deletion.run(() async {
      await _transactionRepository.deleteTransaction(transactionId);
      _notifier.markChanged();
    });
  }

  Future<Transaction> fetchById(String id) =>
      _transactionRepository.getTransactionById(id);

  static String newId() => _uuid.v4();
}
