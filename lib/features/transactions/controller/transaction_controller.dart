import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/receipt_store.dart';
import 'package:finance_tracker/data/repositories/savings_goal_repository.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/entities/transaction_summary.dart';
import 'package:finance_tracker/domain/services/avatar_rules.dart';
import 'package:finance_tracker/domain/services/note_tags.dart';
import 'package:finance_tracker/domain/services/savings_split.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
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

/// List, search, filter, create, edit and delete for income/expense records
/// and transfers between accounts.
class TransactionController extends GetxController {
  TransactionController(
    this._transactionRepository,
    this._accountRepository,
    this._categoryRepository,
    this._notifier, {
    this._receipts,
    this._savingsGoals,
    this._splitRepository,
  });

  final TransactionRepository _transactionRepository;
  final AccountRepository _accountRepository;
  final CategoryRepository _categoryRepository;
  final DataChangeNotifier _notifier;

  /// Null where receipts are not available (tests without storage).
  final ReceiptStore? _receipts;

  /// Null where savings goals are not available (tests without them).
  final SavingsGoalRepository? _savingsGoals;

  /// Null where split groups are not available (tests without them).
  final SplitRepository? _splitRepository;

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

  /// The split group behind derived rows, keyed by expense/settlement id.
  final RxMap<String, SplitLink> splitLinks = <String, SplitLink>{}.obs;

  /// Every stored category row (including inactive and deleted ones), used to
  /// resolve names and icons for display so rows never lose their label when a
  /// category is switched off, deleted, or tombstoned by sync. Pickers and the
  /// filter sheet keep using [categories].
  final RxList<Category> categoryIndex = <Category>[].obs;
  final RxnString lookupError = RxnString();
  final RxBool lookupsLoaded = false.obs;

  /// Tags from the newest notes, suggested in the form.
  final RxList<String> recentTags = <String>[].obs;

  /// Goals an income can put money into; empty when they cannot be loaded.
  final RxList<SavingsGoal> goals = <SavingsGoal>[].obs;

  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();

  int _generation = 0;

  bool get hasActiveFilters =>
      typeFilter.value != null ||
      accountFilter.value != null ||
      categoryFilter.value != null ||
      rangeFilter.value != null;

  final Rx<Decimal> _totalInflow = Decimal.zero.obs;
  final Rx<Decimal> _totalOutflow = Decimal.zero.obs;
  final RxInt totalCount = 0.obs;

  Decimal get totalInflow => _totalInflow.value;
  Decimal get totalOutflow => _totalOutflow.value;
  Decimal get netAmount => _totalInflow.value - _totalOutflow.value;

  // GetX does not dispose workers, and the notifier outlives this
  // controller, so without this a closed controller keeps reloading.
  late final Worker _changes;

  @override
  void onClose() {
    _changes.dispose();
    super.onClose();
  }

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
    _changes = ever<int>(_notifier.version, (_) {
      loadLookups();
      load(silent: true);
    });
  }

  Future<void> loadLookups() async {
    try {
      final (
        List<Account> a,
        List<Category> c,
        List<Category> all,
      ) = await wait3(
        _accountRepository.getAccounts(),
        _categoryRepository.getCategories(),
        _categoryRepository.getAllCategories(),
      );
      accounts.assignAll(a.where((Account x) => x.isActive));
      categories.assignAll(c);
      categoryIndex.assignAll(all);
      lookupError.value = null;
    } on AppException catch (failure) {
      lookupError.value = failure.message;
    } finally {
      lookupsLoaded.value = true;
    }
    try {
      final List<String> notes = await _transactionRepository.getTaggedNotes();
      recentTags.assignAll(NoteTags.of(notes.join(' ')).take(8));
    } on AppException {
      // Only suggestions: typing a #tag in the note still works without them.
    }
    final SavingsGoalRepository? savingsGoals = _savingsGoals;
    if (savingsGoals == null) return;
    try {
      goals.assignAll(await savingsGoals.getSavingsGoals());
    } on AppException {
      // The split section just stays empty; the income can still be saved.
    }
  }

  Category? categoryOf(String? id) {
    if (id == null) return null;
    for (final Category c in categoryIndex) {
      if (c.id == id) return c;
    }
    return null;
  }

  String accountName(String id) {
    for (final Account a in accounts) {
      if (a.id == id) return a.name;
    }
    return 'Account'.tr;
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

  Future<TransactionSummary> _fetchSummary() =>
      _transactionRepository.getTransactionSummary(
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
      );

  /// Reloads from the first page and computes totals for the full dataset.
  /// A [silent] reload keeps the list visible.
  Future<void> load({bool silent = false}) async {
    final int generation = ++_generation;
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final (List<Transaction> page, TransactionSummary summary) = await wait2(
        _fetch(0),
        _fetchSummary(),
      );
      if (generation != _generation) return;
      items.assignAll(page);
      _loadSplitLinks(page);
      _totalInflow.value = summary.totalInflow;
      _totalOutflow.value = summary.totalOutflow;
      totalCount.value = summary.totalCount;
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
      _loadSplitLinks(page);
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
  /// [newReceipt] replaces the receipt photo; [removeReceipt] drops it.
  /// [savings] puts parts of an income into goals; it is ignored for an
  /// expense, which drops any savings it had.
  Future<bool> saveTransaction({
    required String id,
    Transaction? existing,
    required TransactionType type,
    required Decimal amount,
    required String accountId,
    required String? categoryId,
    required DateTime date,
    required String? note,
    ({Uint8List bytes, String fileName})? newReceipt,
    bool removeReceipt = false,
    List<SavingsPart> savings = const <SavingsPart>[],
  }) {
    return save.run(() async {
      final List<SavingsPart> wanted = type == TransactionType.income
          ? savings
          : const <SavingsPart>[];
      final String? invalid = SavingsSplit.validate(
        type: type,
        amount: amount,
        parts: wanted,
      );
      if (invalid != null) throw UnexpectedFailure(invalid.tr);
      if (newReceipt != null) {
        final AvatarProblem? problem = AvatarRules.check(
          fileName: newReceipt.fileName,
          byteLength: newReceipt.bytes.length,
        );
        if (problem != null) throw StorageFailure(problem.message);
      }
      final DateTime now = DateTime.now();
      // The row, not the form's copy: a sync may have linked a photo since
      // the form opened.
      final String? attachmentUrl = existing == null || removeReceipt
          ? null
          : (await _transactionRepository.getTransactionById(id)).attachmentUrl;
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
        attachmentUrl: attachmentUrl,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      final List<SavingsContribution> current = await _transactionRepository
          .getContributions(id);
      final SplitChanges changes = SavingsSplit.diff(
        transactionId: id,
        current: current,
        wanted: wanted,
        newId: newId,
        now: now,
      );
      // A create that finds rows is a retry of a save that already committed
      // (e.g. after a receipt failure): update, or the goals get a second row.
      if (existing == null && current.isEmpty) {
        await _transactionRepository.createTransaction(
          transaction,
          contributions: changes.inserts,
        );
      } else {
        await _transactionRepository.updateTransaction(
          transaction,
          savings: changes,
        );
      }
      _notifier.markChanged();
      await _keepReceipt(id, newReceipt, removeReceipt);
    });
  }

  /// After the row is saved, so a failed save leaves no photo behind. A
  /// retried save of the same form stages the photo again.
  Future<void> _keepReceipt(
    String id,
    ({Uint8List bytes, String fileName})? newReceipt,
    bool removeReceipt,
  ) async {
    final ReceiptStore? receipts = _receipts;
    if (receipts == null) return;
    try {
      if (newReceipt != null) {
        await receipts.stage(id, newReceipt.bytes, newReceipt.fileName);
      } else if (removeReceipt) {
        await receipts.markRemoved(id);
      }
    } on AppException {
      rethrow;
    } on Object {
      throw StorageFailure(
        'The transaction was saved, but the receipt photo could not be kept. Save again to retry.'
            .tr,
      );
    }
  }

  /// The group name of every derived row on screen, for the small chip.
  void _loadSplitLinks(List<Transaction> page) {
    final SplitRepository? repository = _splitRepository;
    if (repository == null) return;
    final List<String> expenseIds = <String>[
      for (final Transaction t in page)
        if (t.splitExpenseId != null) t.splitExpenseId!,
    ];
    final List<String> settlementIds = <String>[
      for (final Transaction t in page)
        if (t.splitSettlementId != null) t.splitSettlementId!,
    ];
    if (expenseIds.isEmpty && settlementIds.isEmpty) return;
    repository
        .getLinks(expenseIds: expenseIds, settlementIds: settlementIds)
        .then((Map<String, SplitLink> links) {
          splitLinks.addAll(links);
        })
        .catchError((Object _) {});
  }

  /// The group name behind [t], or null for a plain row.
  String? groupLabelOf(Transaction t) {
    final String? id = t.splitExpenseId ?? t.splitSettlementId;
    if (id == null) return null;
    return splitLinks[id]?.groupName;
  }

  Future<bool> deleteTransaction(String transactionId) {
    return deletion.run(() async {
      final ReceiptStore? receipts = _receipts;
      final Transaction tx = await _transactionRepository.getTransactionById(
        transactionId,
      );
      if (tx.splitExpenseId != null || tx.splitSettlementId != null) {
        throw const UnexpectedFailure(
          'Open it in the group to change or delete it',
        );
      }
      bool hadReceipt = false;
      if (receipts != null) {
        hadReceipt =
            tx.attachmentUrl != null ||
            await receipts.localFile(transactionId) != null;
      }
      await _transactionRepository.deleteTransaction(transactionId);
      _notifier.markChanged();
      if (hadReceipt) {
        try {
          await receipts!.markRemoved(transactionId);
        } on Object {
          // Best effort: the row is gone; the file is left, shown to nobody.
        }
      }
    });
  }

  /// The live savings rows of an income, for the form.
  Future<List<SavingsContribution>> contributionsOf(String transactionId) =>
      _transactionRepository.getContributions(transactionId);

  Future<Transaction> fetchById(String id) =>
      _transactionRepository.getTransactionById(id);

  /// Both legs of a transfer, or null when it is gone.
  Future<TransferLegs?> fetchTransfer(String transferId) =>
      _transactionRepository.getTransfer(transferId);

  /// Records a transfer, or edits [existing]. An edit updates the rows in
  /// place when [TransferLegs.canUpdateInPlace] allows; otherwise the
  /// transfer is replaced by new rows with [newIds] (generated once per form,
  /// so a retried save is idempotent). Returns the saved legs, or null on
  /// failure (the message is in [save]).
  Future<TransferLegs?> saveTransfer({
    required TransferIds newIds,
    TransferLegs? existing,
    required String fromAccountId,
    required String toAccountId,
    required Decimal amount,
    required DateTime date,
    required String? note,
  }) async {
    TransferLegs? saved;
    final bool ok = await save.run(() async {
      final DateTime now = DateTime.now();
      if (existing != null && existing.canUpdateInPlace(fromAccountId)) {
        saved = TransferLegs.build(
          transferId: existing.transferId,
          outgoingId: existing.outgoing.id,
          incomingId: existing.incoming.id,
          fromAccountId: fromAccountId,
          toAccountId: toAccountId,
          amount: amount,
          date: date,
          note: note,
          now: now,
          userId: existing.outgoing.userId,
          createdAt: existing.outgoing.createdAt,
        );
        await _transactionRepository.updateTransfer(saved!);
      } else {
        saved = TransferLegs.build(
          transferId: newIds.transferId,
          outgoingId: newIds.outgoingId,
          incomingId: newIds.incomingId,
          fromAccountId: fromAccountId,
          toAccountId: toAccountId,
          amount: amount,
          date: date,
          note: note,
          now: now,
        );
        await _transactionRepository.createTransfer(
          saved!,
          replacing: existing?.transferId,
        );
      }
      _notifier.markChanged();
    });
    return ok ? saved : null;
  }

  /// Deletes both legs of a transfer.
  Future<bool> deleteTransfer(String transferId) {
    return deletion.run(() async {
      await _transactionRepository.deleteTransfer(transferId);
      _notifier.markChanged();
    });
  }

  static String newId() => _uuid.v4();
}

/// Ids for a new transfer, generated once per form.
class TransferIds {
  TransferIds()
    : transferId = TransactionController.newId(),
      outgoingId = TransactionController.newId(),
      incomingId = TransactionController.newId();

  final String transferId;
  final String outgoingId;
  final String incomingId;
}

/// Arguments for the transfer form route: a preselected source account for
/// a new transfer, or the transfer to edit.
class TransferFormArgs {
  const TransferFormArgs({this.fromAccountId, this.transferId});

  final String? fromAccountId;
  final String? transferId;
}
