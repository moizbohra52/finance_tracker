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
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';

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
    return List<Category>.of(_f.categories);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeTransactionRepository implements TransactionRepository {
  FakeTransactionRepository(this._f);
  final FakeFinance _f;

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
  Future<Transaction> getTransactionById(String id) async {
    _f.throwPending();
    return _f.transactions.firstWhere((Transaction t) => t.id == id);
  }

  @override
  Future<void> createTransaction(
    Transaction transaction, {
    bool onlyIfAbsent = false,
  }) async {
    _f.throwPending();
    if (onlyIfAbsent &&
        _f.transactions.any((Transaction t) => t.id == transaction.id)) {
      return;
    }
    _f.transactions
      ..removeWhere((Transaction t) => t.id == transaction.id)
      ..add(transaction);
  }

  @override
  Future<void> updateTransaction(Transaction transaction) async {
    _f.throwPending();
    final int i = _f.transactions.indexWhere(
      (Transaction t) => t.id == transaction.id,
    );
    _f.transactions[i] = transaction;
  }

  @override
  Future<void> deleteTransaction(String id) async {
    _f.throwPending();
    final int i = _f.transactions.indexWhere((Transaction t) => t.id == id);
    _f.transactions[i] = _f.transactions[i].copyWith(deletedAt: DateTime.now());
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
