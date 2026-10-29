import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/app_repositories.dart';
import 'package:finance_tracker/data/repositories/budget_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/notification_repository.dart';
import 'package:finance_tracker/data/repositories/recurring_repository.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/data/repositories/savings_goal_repository.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/entities/transaction_summary.dart';
import 'package:finance_tracker/domain/services/savings_split.dart';
import 'package:finance_tracker/domain/services/split_balances.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';

/// In-memory finance data shared by the fake repositories. [nextError] makes
/// the next repository call fail once.
class FakeFinance {
  FakeFinance() {
    repositories = AppRepositories(
      accounts: FakeAccountRepository(this),
      categories: FakeCategoryRepository(this),
      transactions: FakeTransactionRepository(this),
      contacts: FakeContactRepository(this),
      budgets: FakeBudgetRepository(this),
      recurring: FakeRecurringRepository(this),
      notifications: FakeNotificationRepository(this),
      reminders: FakeReminderRepository(this),
      savingsGoals: FakeSavingsGoalRepository(this),
      split: FakeSplitRepository(this),
    );
  }

  late final AppRepositories repositories;
  final List<Account> accounts = <Account>[];
  final List<Transaction> transactions = <Transaction>[];
  final List<Contact> contacts = <Contact>[];
  final List<ContactTransaction> contactTransactions = <ContactTransaction>[];
  final List<Budget> budgets = <Budget>[];
  final List<RecurringTransaction> recurring = <RecurringTransaction>[];
  final List<Reminder> reminders = <Reminder>[];
  final List<SavingsGoal> savingsGoals = <SavingsGoal>[];
  final List<SavingsContribution> contributions = <SavingsContribution>[];
  final List<SplitGroup> splitGroups = <SplitGroup>[];
  final List<SplitMember> splitMembers = <SplitMember>[];
  final List<SplitExpense> splitExpenses = <SplitExpense>[];
  final List<SplitPart> splitParts = <SplitPart>[];
  final List<SplitSettlement> splitSettlements = <SplitSettlement>[];

  /// FCM token rows by device id, with their `active` flag.
  final Map<String, ({String token, bool active})> deviceTokens =
      <String, ({String token, bool active})>{};

  /// Notification rows by id (what `raiseOnce` stored), oldest first. A row
  /// that was read also has a `read_at` entry.
  final Map<String, Map<String, String>> notifications =
      <String, Map<String, String>>{};
  int notificationWrites = 0;
  final List<Category> categories = <Category>[
    Category(
      id: 'cat-food',
      name: 'Food & Dining',
      type: CategoryType.expense,
      icon: 'food',
      isSystem: true,
      isActive: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    Category(
      id: 'cat-salary',
      name: 'Salary',
      type: CategoryType.income,
      icon: 'salary',
      isSystem: true,
      isActive: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  AppException? nextError;

  /// While set, reading a transaction's savings throws this. Not an
  /// [AppException], like a local database or decoding error.
  Error? contributionsError;

  /// While set, every repository call fails (use when several controllers
  /// load at startup and a single [nextError] would hit only one of them).
  AppException? failAll;

  void throwPending() {
    if (failAll != null) throw failAll!;
    final AppException? error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  Account addAccount(String name, String opening, {String id = 'acc-1'}) {
    final Account account = Account(
      id: id,
      userId: 'user-1',
      name: name,
      type: AccountType.cash,
      openingBalance: Decimal.parse(opening),
      openingBalanceDate: DateTime(2026),
      isActive: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    accounts.add(account);
    return account;
  }

  Transaction addTransaction({
    required String id,
    required TransactionType type,
    required String amount,
    String accountId = 'acc-1',
    String? categoryId,
    String? note,
    DateTime? date,
    String? attachmentUrl,
  }) {
    final Transaction t = Transaction(
      id: id,
      userId: 'user-1',
      accountId: accountId,
      categoryId: categoryId,
      type: type,
      amount: Decimal.parse(amount),
      transactionDate: date ?? DateTime.now(),
      note: note,
      attachmentUrl: attachmentUrl,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    transactions.add(t);
    return t;
  }
}

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository(this._f);
  final FakeFinance _f;

  @override
  Future<List<Account>> getAccounts() async {
    _f.throwPending();
    return _f.accounts.where((Account a) => a.deletedAt == null).toList();
  }

  @override
  Future<Account> getAccountById(String id) async {
    _f.throwPending();
    return _f.accounts.firstWhere((Account a) => a.id == id);
  }

  @override
  Future<void> createAccount(Account account) async {
    _f.throwPending();
    _f.accounts
      ..removeWhere((Account a) => a.id == account.id)
      ..add(account);
  }

  @override
  Future<void> updateAccount(Account account) async {
    _f.throwPending();
    final int i = _f.accounts.indexWhere((Account a) => a.id == account.id);
    _f.accounts[i] = account;
  }

  @override
  Future<void> deleteAccount(String id) async {
    _f.throwPending();
    final int i = _f.accounts.indexWhere((Account a) => a.id == id);
    _f.accounts[i] = _f.accounts[i].copyWith(deletedAt: DateTime.now());
  }
}

class FakeCategoryRepository implements CategoryRepository {
  FakeCategoryRepository(this._f);
  final FakeFinance _f;

  @override
  Future<List<Category>> getCategories() async {
    _f.throwPending();
    return _f.categories.where((Category c) => c.deletedAt == null).toList();
  }

  @override
  Future<void> createCategory(Category category) async {
    _f.throwPending();
    _f.categories
      ..removeWhere((Category c) => c.id == category.id)
      ..add(category);
  }

  @override
  Future<void> updateCategory(Category category) async {
    _f.throwPending();
    final int i = _f.categories.indexWhere((Category c) => c.id == category.id);
    _f.categories[i] = category;
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    _f.throwPending();
    final int i = _f.categories.indexWhere((Category c) => c.id == categoryId);
    final Category c = _f.categories[i];
    _f.categories[i] = Category(
      id: c.id,
      userId: c.userId,
      name: c.name,
      type: c.type,
      icon: c.icon,
      isSystem: c.isSystem,
      isActive: c.isActive,
      createdAt: c.createdAt,
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeTransactionRepository implements TransactionRepository {
  FakeTransactionRepository(this._f);
  final FakeFinance _f;

  @override
  Future<List<String>> getTaggedNotes({int limit = 100}) async {
    _f.throwPending();
    final List<Transaction> rows =
        _f.transactions
            .where(
              (Transaction t) =>
                  t.deletedAt == null && (t.note ?? '').contains('#'),
            )
            .toList()
          ..sort(
            (Transaction a, Transaction b) =>
                b.transactionDate.compareTo(a.transactionDate),
          );
    return <String>[for (final Transaction t in rows.take(limit)) t.note!];
  }

  @override
  Future<List<Transaction>> getTransactions({
    String? accountId,
    String? categoryId,
    String? contactId,
    TransactionType? type,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) async {
    _f.throwPending();
    final String term = (search ?? '').trim().toLowerCase();
    final List<Transaction> rows =
        _f.transactions.where((Transaction t) {
          if (t.deletedAt != null) return false;
          if (accountId != null && t.accountId != accountId) return false;
          if (categoryId != null && t.categoryId != categoryId) return false;
          if (type != null && t.type != type) return false;
          if (startDate != null && t.transactionDate.isBefore(startDate)) {
            return false;
          }
          if (endDate != null && t.transactionDate.isAfter(endDate)) {
            return false;
          }
          if (term.isNotEmpty && !(t.note ?? '').toLowerCase().contains(term)) {
            return false;
          }
          return true;
        }).toList()..sort(
          (Transaction a, Transaction b) =>
              b.transactionDate.compareTo(a.transactionDate),
        );
    return rows.skip(offset).take(limit).toList();
  }

  @override
  Future<List<Transaction>> getAllTransactions({
    String? accountId,
    DateTime? start,
    DateTime? end,
  }) => getTransactions(
    accountId: accountId,
    startDate: start,
    endDate: end?.subtract(const Duration(milliseconds: 1)),
    limit: 100000,
  );

  @override
  Future<TransactionSummary> getTransactionSummary({
    String? accountId,
    String? categoryId,
    String? contactId,
    TransactionType? type,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final List<Transaction> all = await getTransactions(
      accountId: accountId,
      categoryId: categoryId,
      contactId: contactId,
      type: type,
      search: search,
      startDate: startDate,
      endDate: endDate,
      limit: 1000000,
    );
    Decimal inflow = Decimal.zero;
    Decimal outflow = Decimal.zero;
    for (final Transaction t in all) {
      final bool isInflow =
          t.type == TransactionType.income ||
          t.type == TransactionType.transfer_in ||
          t.type == TransactionType.adjustment_in ||
          t.type == TransactionType.payment_received ||
          t.type == TransactionType.opening_balance;
      final bool isOutflow =
          t.type == TransactionType.expense ||
          t.type == TransactionType.transfer_out ||
          t.type == TransactionType.adjustment_out ||
          t.type == TransactionType.payment_made;
      if (isInflow) {
        inflow += t.amount;
      } else if (isOutflow) {
        outflow += t.amount;
      }
    }
    return TransactionSummary(
      totalInflow: inflow,
      totalOutflow: outflow,
      totalCount: all.length,
    );
  }

  @override
  Future<Transaction> getTransactionById(String id) async {
    _f.throwPending();
    return _f.transactions.firstWhere((Transaction t) => t.id == id);
  }

  @override
  Future<void> createTransaction(
    Transaction transaction, {
    bool onlyIfAbsent = false,
    List<SavingsContribution> contributions = const <SavingsContribution>[],
  }) async {
    _f.throwPending();
    if (onlyIfAbsent &&
        _f.transactions.any((Transaction t) => t.id == transaction.id)) {
      return;
    }
    _f.transactions
      ..removeWhere((Transaction t) => t.id == transaction.id)
      ..add(transaction);
    for (final SavingsContribution c in contributions) {
      _f.contributions
        ..removeWhere((SavingsContribution x) => x.id == c.id)
        ..add(c);
    }
  }

  @override
  Future<void> updateTransaction(
    Transaction transaction, {
    SplitChanges? savings,
  }) async {
    _f.throwPending();
    final int i = _f.transactions.indexWhere(
      (Transaction t) => t.id == transaction.id,
    );
    _f.transactions[i] = transaction;
    if (savings == null) return;
    _f.contributions.addAll(savings.inserts);
    for (final SavingsContribution c in savings.updates) {
      final int j = _f.contributions.indexWhere(
        (SavingsContribution x) => x.id == c.id,
      );
      _f.contributions[j] = c;
    }
    _softDeleteContributions(
      (SavingsContribution c) => savings.deletes.contains(c.id),
    );
  }

  @override
  Future<void> deleteTransaction(String id) async {
    _f.throwPending();
    final int i = _f.transactions.indexWhere((Transaction t) => t.id == id);
    _f.transactions[i] = _f.transactions[i].copyWith(deletedAt: DateTime.now());
    _softDeleteContributions((SavingsContribution c) => c.transactionId == id);
  }

  @override
  Future<List<SavingsContribution>> getContributions(
    String transactionId,
  ) async {
    _f.throwPending();
    final Error? failure = _f.contributionsError;
    if (failure != null) throw failure;
    return _f.contributions
        .where(
          (SavingsContribution c) =>
              c.transactionId == transactionId && c.deletedAt == null,
        )
        .toList();
  }

  void _softDeleteContributions(bool Function(SavingsContribution) test) {
    for (int i = 0; i < _f.contributions.length; i++) {
      final SavingsContribution c = _f.contributions[i];
      if (c.deletedAt == null && test(c)) {
        _f.contributions[i] = c.copyWith(deletedAt: DateTime.now());
      }
    }
  }

  @override
  Future<TransferLegs?> getTransfer(String transferId) async {
    _f.throwPending();
    return TransferLegs.fromRows(
      _f.transactions.where((Transaction t) => t.transferId == transferId),
    );
  }

  @override
  Future<void> createTransfer(TransferLegs legs, {String? replacing}) async {
    _f.throwPending();
    if (replacing != null) _tombstone(replacing);
    for (final Transaction leg in <Transaction>[legs.outgoing, legs.incoming]) {
      _f.transactions
        ..removeWhere((Transaction t) => t.id == leg.id)
        ..add(leg);
    }
  }

  @override
  Future<void> updateTransfer(TransferLegs legs) async {
    _f.throwPending();
    for (final Transaction leg in <Transaction>[legs.outgoing, legs.incoming]) {
      final int i = _f.transactions.indexWhere(
        (Transaction t) => t.id == leg.id,
      );
      _f.transactions[i] = leg;
    }
  }

  @override
  Future<void> deleteTransfer(String transferId) async {
    _f.throwPending();
    _tombstone(transferId);
  }

  void _tombstone(String transferId) {
    for (int i = 0; i < _f.transactions.length; i++) {
      final Transaction t = _f.transactions[i];
      if (t.transferId == transferId && t.deletedAt == null) {
        _f.transactions[i] = t.copyWith(deletedAt: DateTime.now());
      }
    }
  }
}

class FakeContactRepository implements ContactRepository {
  FakeContactRepository(this._f);
  final FakeFinance _f;

  @override
  Future<List<Contact>> getContacts() async {
    _f.throwPending();
    return _f.contacts.where((Contact c) => c.deletedAt == null).toList();
  }

  @override
  Future<Contact> getContactById(String id) async {
    _f.throwPending();
    return _f.contacts.firstWhere((Contact c) => c.id == id);
  }

  @override
  Future<void> createContact(Contact contact) async {
    _f.throwPending();
    _f.contacts
      ..removeWhere((Contact c) => c.id == contact.id)
      ..add(contact);
  }

  @override
  Future<void> updateContact(Contact contact) async {
    _f.throwPending();
    final int i = _f.contacts.indexWhere((Contact c) => c.id == contact.id);
    _f.contacts[i] = contact;
  }

  @override
  Future<void> deleteContact(String id) async {
    _f.throwPending();
    _f.contacts.removeWhere((Contact c) => c.id == id);
  }

  @override
  Future<List<ContactTransaction>> getContactTransactions(
    String contactId,
  ) async {
    _f.throwPending();
    return _f.contactTransactions
        .where((ContactTransaction t) => t.contactId == contactId)
        .toList();
  }

  @override
  Future<List<ContactTransaction>> getAllContactTransactions() async {
    _f.throwPending();
    return List<ContactTransaction>.of(_f.contactTransactions);
  }

  @override
  Future<void> createContactTransaction(ContactTransaction t) async {
    _f.throwPending();
    _f.contactTransactions
      ..removeWhere((ContactTransaction x) => x.id == t.id)
      ..add(t);
  }

  @override
  Future<void> updateContactTransaction(ContactTransaction t) async {
    _f.throwPending();
  }

  @override
  Future<void> deleteContactTransaction(String id) async {
    _f.throwPending();
    _f.contactTransactions.removeWhere((ContactTransaction x) => x.id == id);
  }
}

class FakeBudgetRepository implements BudgetRepository {
  FakeBudgetRepository(this._f);
  final FakeFinance _f;

  @override
  Future<List<Budget>> getBudgets() async {
    _f.throwPending();
    return _f.budgets.where((Budget b) => b.deletedAt == null).toList();
  }

  @override
  Future<void> createBudget(Budget budget) async {
    _f.throwPending();
    _f.budgets
      ..removeWhere((Budget b) => b.id == budget.id)
      ..add(budget);
  }

  @override
  Future<void> updateBudget(Budget budget) async {
    _f.throwPending();
    final int i = _f.budgets.indexWhere((Budget b) => b.id == budget.id);
    _f.budgets[i] = budget;
  }

  @override
  Future<void> deleteBudget(String id) async {
    _f.throwPending();
    _f.budgets.removeWhere((Budget b) => b.id == id);
  }
}

class FakeSavingsGoalRepository implements SavingsGoalRepository {
  FakeSavingsGoalRepository(this._f);
  final FakeFinance _f;

  @override
  Future<List<SavingsGoal>> getSavingsGoals() async {
    _f.throwPending();
    // Same rule as the real repository: live rows whose income still exists.
    final Set<String> liveTransactions = <String>{
      for (final Transaction t in _f.transactions)
        if (t.deletedAt == null) t.id,
    };
    final Map<String, Decimal> sums = SavingsSplit.sumByGoal(
      _f.contributions.where(
        (SavingsContribution c) =>
            c.deletedAt == null && liveTransactions.contains(c.transactionId),
      ),
    );
    return <SavingsGoal>[
      for (final SavingsGoal g in _f.savingsGoals)
        if (g.deletedAt == null)
          SavingsGoal(
            id: g.id,
            userId: g.userId,
            name: g.name,
            targetAmount: g.targetAmount,
            savedAmount: g.savedAmount,
            contributedAmount: sums[g.id],
            targetDate: g.targetDate,
            createdAt: g.createdAt,
            updatedAt: g.updatedAt,
          ),
    ];
  }

  @override
  Future<void> createSavingsGoal(SavingsGoal goal) async {
    _f.throwPending();
    _f.savingsGoals
      ..removeWhere((SavingsGoal g) => g.id == goal.id)
      ..add(goal);
  }

  @override
  Future<void> updateSavingsGoal(SavingsGoal goal) async {
    _f.throwPending();
    final int i = _f.savingsGoals.indexWhere(
      (SavingsGoal g) => g.id == goal.id,
    );
    _f.savingsGoals[i] = goal;
  }

  @override
  Future<void> deleteSavingsGoal(String id) async {
    _f.throwPending();
    _f.savingsGoals.removeWhere((SavingsGoal g) => g.id == id);
    final DateTime now = DateTime.now();
    for (int i = 0; i < _f.contributions.length; i++) {
      final SavingsContribution c = _f.contributions[i];
      if (c.goalId == id && c.deletedAt == null) {
        _f.contributions[i] = c.copyWith(deletedAt: now);
      }
    }
  }
}

class FakeRecurringRepository implements RecurringRepository {
  FakeRecurringRepository(this._f);
  final FakeFinance _f;

  @override
  Future<List<RecurringTransaction>> getAll() async {
    _f.throwPending();
    return List<RecurringTransaction>.of(_f.recurring);
  }

  @override
  Future<void> create(RecurringTransaction rule) async {
    _f.throwPending();
    _f.recurring
      ..removeWhere((RecurringTransaction r) => r.id == rule.id)
      ..add(rule);
  }

  @override
  Future<void> update(RecurringTransaction rule) async {
    _f.throwPending();
    final int i = _f.recurring.indexWhere(
      (RecurringTransaction r) => r.id == rule.id,
    );
    _f.recurring[i] = rule;
  }

  @override
  Future<void> delete(String id) async {
    _f.throwPending();
    _f.recurring.removeWhere((RecurringTransaction r) => r.id == id);
  }
}

class FakeReminderRepository implements ReminderRepository {
  FakeReminderRepository(this._f);
  final FakeFinance _f;

  @override
  Future<List<Reminder>> getAll() async {
    _f.throwPending();
    return _f.reminders.where((Reminder r) => r.deletedAt == null).toList();
  }

  @override
  Future<void> create(Reminder reminder) async {
    _f.throwPending();
    _f.reminders
      ..removeWhere((Reminder r) => r.id == reminder.id)
      ..add(reminder);
  }

  @override
  Future<void> update(Reminder reminder) async {
    _f.throwPending();
    final int i = _f.reminders.indexWhere((Reminder r) => r.id == reminder.id);
    _f.reminders[i] = reminder;
  }

  @override
  Future<void> delete(String id) async {
    _f.throwPending();
    _f.reminders.removeWhere((Reminder r) => r.id == id);
  }
}

class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository(this._f);
  final FakeFinance _f;

  @override
  Future<bool> raiseOnce({
    required String id,
    required String type,
    required String title,
    required String body,
    required String referenceId,
  }) async {
    _f.throwPending();
    _f.notificationWrites++;
    if (_f.notifications.containsKey(id)) return false;
    _f.notifications[id] = <String, String>{
      'type': type,
      'title': title,
      'body': body,
      'reference_id': referenceId,
    };
    return true;
  }

  AppNotification _row(int index, String id, Map<String, String> row) =>
      AppNotification(
        id: id,
        type: row['type']!,
        title: row['title']!,
        body: row['body'],
        referenceId: row['reference_id'],
        readAt: row['read_at'] == null ? null : DateTime(2026, 2),
        createdAt: DateTime(2026).add(Duration(minutes: index)),
      );

  @override
  Future<List<AppNotification>> getPage({
    int limit = 30,
    int offset = 0,
  }) async {
    _f.throwPending();
    final List<AppNotification> all = <AppNotification>[
      for (final (int i, MapEntry<String, Map<String, String>> e)
          in _f.notifications.entries.indexed)
        _row(i, e.key, e.value),
    ].reversed.toList();
    return all.skip(offset).take(limit).toList();
  }

  @override
  Future<int> unreadCount() async {
    _f.throwPending();
    return _f.notifications.values
        .where((Map<String, String> r) => r['read_at'] == null)
        .length;
  }

  @override
  Future<void> markRead(String id) async {
    _f.throwPending();
    _f.notifications[id]?['read_at'] = 'now';
  }

  @override
  Future<void> markAllRead() async {
    _f.throwPending();
    for (final Map<String, String> row in _f.notifications.values) {
      row['read_at'] = 'now';
    }
  }

  @override
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    required String deviceId,
  }) async {
    _f.throwPending();
    _f.deviceTokens[deviceId] = (token: token, active: true);
  }

  @override
  Future<void> deactivateDeviceToken(String deviceId) async {
    _f.throwPending();
    final ({String token, bool active})? current = _f.deviceTokens[deviceId];
    if (current != null) {
      _f.deviceTokens[deviceId] = (token: current.token, active: false);
    }
  }
}

class FakeSplitRepository implements SplitRepository {
  FakeSplitRepository(this._f);
  final FakeFinance _f;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<List<SplitGroupSummary>> getGroups() async {
    _f.throwPending();
    final List<SplitGroupSummary> groups = <SplitGroupSummary>[];
    for (final SplitGroup g in _f.splitGroups) {
      if (g.deletedAt != null) continue;
      final List<SplitMember> members = _f.splitMembers
          .where((SplitMember m) => m.groupId == g.id && m.isLive)
          .toList();
      final GroupBalances balances = _balances(g.id);
      groups.add(
        SplitGroupSummary(
          group: g,
          memberCount: members.length,
          userNet: balances.netOf(SplitIds.member(g.id, null)),
        ),
      );
    }
    return groups;
  }

  @override
  Future<SplitGroup> getGroup(String groupId) async {
    _f.throwPending();
    for (final SplitGroup g in _f.splitGroups) {
      if (g.id == groupId) return g;
    }
    throw const DatabaseFailure();
  }

  @override
  Future<List<SplitMember>> getMembers(String groupId) async {
    _f.throwPending();
    final List<SplitMember> members = _f.splitMembers
        .where((SplitMember m) => m.groupId == groupId && m.isLive)
        .toList();
    members.sort((SplitMember a, SplitMember b) {
      final int byMe = (b.isMe ? 1 : 0).compareTo(a.isMe ? 1 : 0);
      return byMe != 0 ? byMe : a.id.compareTo(b.id);
    });
    return members;
  }

  @override
  Future<void> saveGroup({
    required String groupId,
    required String name,
    required List<String> friendContactIds,
  }) async {
    _f.throwPending();
    if (name.trim().isEmpty) {
      throw const UnexpectedFailure('Give the group a name');
    }
    final Set<String> friends = friendContactIds.toSet();
    if (friends.isEmpty) {
      throw const UnexpectedFailure('Add at least one friend');
    }
    final DateTime now = DateTime.now();
    for (final SplitMember member in _f.splitMembers) {
      if (member.groupId != groupId ||
          member.isMe ||
          member.deletedAt != null ||
          friends.contains(member.contactId)) {
        continue;
      }
      final bool hasActivity =
          _f.splitParts.any(
            (SplitPart p) => p.memberId == member.id && p.isLive,
          ) ||
          _f.splitSettlements.any(
            (SplitSettlement s) =>
                (s.fromMemberId == member.id || s.toMemberId == member.id) &&
                s.isLive,
          );
      if (hasActivity) {
        throw const UnexpectedFailure(
          "This friend is in an expense or settlement and can't be removed",
        );
      }
    }
    final SplitGroup existing = _f.splitGroups.firstWhere(
      (SplitGroup g) => g.id == groupId,
      orElse: () => SplitGroup(
        id: groupId,
        userId: '',
        name: '',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final SplitGroup group = SplitGroup(
      id: groupId,
      userId: '',
      name: name.trim(),
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    _f.splitGroups
      ..removeWhere((SplitGroup g) => g.id == groupId)
      ..add(group);
    final SplitMember me = SplitMember(
      id: SplitIds.member(groupId, null),
      userId: '',
      groupId: groupId,
      contactId: null,
      createdAt: now,
      updatedAt: now,
    );
    _f.splitMembers
      ..removeWhere((SplitMember m) => m.id == me.id)
      ..add(me);
    for (final String contactId in friends) {
      final SplitMember member = SplitMember(
        id: SplitIds.member(groupId, contactId),
        userId: '',
        groupId: groupId,
        contactId: contactId,
        createdAt: now,
        updatedAt: now,
      );
      _f.splitMembers
        ..removeWhere((SplitMember m) => m.id == member.id)
        ..add(member);
    }
    for (final SplitMember m in _f.splitMembers) {
      if (m.groupId == groupId &&
          !m.isMe &&
          !friends.contains(m.contactId) &&
          m.deletedAt == null) {
        _f.splitMembers[_f.splitMembers.indexOf(m)] = m.copyWith(
          deletedAt: now,
        );
      }
    }
  }

  @override
  Future<String?> groupNameBlockingContactDelete(String contactId) async {
    _f.throwPending();
    for (final SplitMember m in _f.splitMembers) {
      if (m.contactId != contactId || !m.isLive) continue;
      for (final SplitGroup g in _f.splitGroups) {
        if (g.id == m.groupId && g.isLive) return g.name;
      }
    }
    return null;
  }

  @override
  Future<Map<String, SplitLink>> getLinks({
    Iterable<String> expenseIds = const <String>[],
    Iterable<String> settlementIds = const <String>[],
  }) async {
    _f.throwPending();
    final Map<String, SplitLink> links = <String, SplitLink>{};
    final Map<String, SplitGroup> liveGroups = <String, SplitGroup>{
      for (final SplitGroup g in _f.splitGroups)
        if (g.isLive) g.id: g,
    };
    for (final SplitExpense e in _f.splitExpenses) {
      final SplitGroup? group = liveGroups[e.groupId];
      if (group != null && expenseIds.contains(e.id)) {
        links[e.id] = SplitLink(
          id: e.id,
          groupId: group.id,
          groupName: group.name,
          isSettlement: false,
        );
      }
    }
    for (final SplitSettlement s in _f.splitSettlements) {
      final SplitGroup? group = liveGroups[s.groupId];
      if (group != null && settlementIds.contains(s.id)) {
        links[s.id] = SplitLink(
          id: s.id,
          groupId: group.id,
          groupName: group.name,
          isSettlement: true,
        );
      }
    }
    return links;
  }

  GroupBalances _balances(String groupId) => SplitBalances.compute(
    meId: SplitIds.member(groupId, null),
    expenses: _f.splitExpenses
        .where((SplitExpense e) => e.groupId == groupId && e.isLive)
        .toList(),
    partsByExpense: <String, List<SplitPart>>{
      for (final SplitExpense e in _f.splitExpenses)
        if (e.groupId == groupId)
          e.id: _f.splitParts
              .where((SplitPart p) => p.splitExpenseId == e.id && p.isLive)
              .toList(),
    },
    settlements: _f.splitSettlements
        .where((SplitSettlement s) => s.groupId == groupId && s.isLive)
        .toList(),
  );

  /// Timestamps the fakes never care about.
  static DateTime get epoch => _epoch;

  @override
  Future<SplitExpenseDetail> getExpense(String expenseId) async {
    _f.throwPending();
    for (final SplitExpense e in _f.splitExpenses) {
      if (e.id == expenseId) {
        return SplitExpenseDetail(
          expense: e,
          parts: _f.splitParts
              .where((SplitPart p) => p.splitExpenseId == expenseId && p.isLive)
              .toList(),
        );
      }
    }
    throw const DatabaseFailure();
  }

  @override
  Future<void> saveExpense({
    required SplitExpense expense,
    required List<SplitPart> parts,
  }) async {
    _f.throwPending();
    // Store/replace by id; derived rows are NOT produced by the fake (the
    // real repository's tests cover them).
    _f.splitExpenses
      ..removeWhere((SplitExpense e) => e.id == expense.id)
      ..add(expense);
    final Set<String> wanted = <String>{
      for (final SplitPart p in parts) SplitIds.part(expense.id, p.memberId),
    };
    final DateTime now = DateTime.now();
    for (int i = 0; i < _f.splitParts.length; i++) {
      final SplitPart p = _f.splitParts[i];
      if (p.splitExpenseId != expense.id || !p.isLive) continue;
      if (!wanted.contains(p.id)) {
        _f.splitParts[i] = p.copyWith(deletedAt: now);
      }
    }
    for (final SplitPart p in parts) {
      final SplitPart row = SplitPart(
        id: SplitIds.part(expense.id, p.memberId),
        userId: '',
        splitExpenseId: expense.id,
        memberId: p.memberId,
        paidAmount: p.paidAmount,
        shareAmount: p.shareAmount,
        shareInput: p.shareInput,
        createdAt: p.createdAt,
        updatedAt: now,
      );
      _f.splitParts
        ..removeWhere((SplitPart x) => x.id == row.id)
        ..add(row);
    }
  }

  @override
  Future<void> deleteExpense(String expenseId) async {
    _f.throwPending();
    final DateTime now = DateTime.now();
    for (int i = 0; i < _f.splitExpenses.length; i++) {
      if (_f.splitExpenses[i].id == expenseId) {
        _f.splitExpenses[i] = _f.splitExpenses[i].copyWith(deletedAt: now);
      }
    }
    for (int i = 0; i < _f.splitParts.length; i++) {
      final SplitPart p = _f.splitParts[i];
      if (p.splitExpenseId == expenseId && p.isLive) {
        _f.splitParts[i] = p.copyWith(deletedAt: now);
      }
    }
  }
}
