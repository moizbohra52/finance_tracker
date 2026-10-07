import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/services/account_balance_calculator.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:get/get.dart';

class TransactionController extends GetxController {
  final TransactionRepository _transactionRepository;
  final AccountRepository _accountRepository;
  final CategoryRepository _categoryRepository;

  TransactionController(this._transactionRepository, this._accountRepository, this._categoryRepository);

  // Observable lists
  final RxList<Transaction> _transactions = <Transaction>[].obs;
  List<Transaction> get transactions => _transactions;

  // Observable lists for dropdowns in forms
  final RxList<Account> _accounts = <Account>[].obs;
  List<Account> get accounts => _accounts;

  final RxList<Category> _categories = <Category>[].obs;
  List<Category> get categories => _categories;

  // Selected transaction
  final Rx<Transaction?> _selectedTransaction = Rx<Transaction?>(null);
  Transaction? get selectedTransaction => _selectedTransaction.value;
  set selectedTransaction(Transaction? value) => _selectedTransaction.value = value;

  // Loading states
  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;
  set isLoading(bool value) => _isLoading.value = value;

  // Error handling
  final RxString _errorMessage = ''.obs;
  String get errorMessage => _errorMessage.value;
  set errorMessage(String value) => _errorMessage.value = value;

  @override
  void onInit() {
    super.onInit();
    // Load transactions for the currently selected account when controller initializes
    loadAccounts();
    loadCategories();
  }

  Future<void> loadAccounts() async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      final accounts = await _accountRepository.getAccounts();
      _accounts.assignAll(accounts);
    } catch (e) {
      _errorMessage.value = e.toString();
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> loadCategories() async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      final categories = await _categoryRepository.getCategories();
      _categories.assignAll(categories);
    } catch (e) {
      _errorMessage.value = e.toString();
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> loadTransactions({
    String? accountId,
    String? categoryId,
    String? contactId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      final transactions = await _transactionRepository.getTransactions(
        accountId: accountId,
        categoryId: categoryId,
        contactId: contactId,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
        offset: offset,
      );
      _transactions.assignAll(transactions);
    } catch (e) {
      _errorMessage.value = e.toString();
    } finally {
      _isLoading.value = false;
    }
  }

  Future<Transaction> getTransactionById(String transactionId) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      final transaction =
          await _transactionRepository.getTransactionById(transactionId);
      _selectedTransaction.value = transaction;
      return transaction;
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> createTransaction(Transaction transaction) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      await _transactionRepository.createTransaction(transaction);
      // Optionally refresh the transaction list
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> updateTransaction(Transaction transaction) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      await _transactionRepository.updateTransaction(transaction);
      // Optionally refresh the transaction list
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> deleteTransaction(String transactionId) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      await _transactionRepository.deleteTransaction(transactionId);
      // Optionally refresh the transaction list
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  // Helper method to calculate balance for an account
  Future<Decimal> calculateAccountBalance(
      String accountId, DateTime asOfDate, AccountRepository accountRepository) async {
    final transactions = await _transactionRepository.getTransactions(
      accountId: accountId,
      endDate: asOfDate,
      limit: 1000, // Adjust as needed
    );

    // Get the account to get opening balance
    final account = await accountRepository.getAccountById(accountId);
    return AccountBalanceCalculator.calculateBalance(
      account.openingBalance,
      transactions,
    );
  }

  void clearTransactions() {
    _transactions.clear();
  }
}