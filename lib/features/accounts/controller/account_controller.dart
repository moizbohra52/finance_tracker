import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:get/get.dart';

class AccountController extends GetxController {
  final AccountRepository _accountRepository;

  AccountController(this._accountRepository);

  // Observable lists
  final RxList<Account> _accounts = <Account>[].obs;
  List<Account> get accounts => _accounts;

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
    loadAccounts();
  }

  Future<void> loadAccounts() async {
    isLoading = true;
    errorMessage = '';
    try {
      final accounts = await _accountRepository.getAccounts();
      _accounts.assignAll(accounts);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  Future<Account> getAccountById(String accountId) async {
    isLoading = true;
    errorMessage = '';
    try {
      final account = await _accountRepository.getAccountById(accountId);
      return account;
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isLoading = false;
    }
  }

  Future<void> createAccount(Account account) async {
    isLoading = true;
    errorMessage = '';
    try {
      await _accountRepository.createAccount(account);
      // Refresh the account list
      await loadAccounts();
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isLoading = false;
    }
  }

  Future<void> updateAccount(Account account) async {
    isLoading = true;
    errorMessage = '';
    try {
      await _accountRepository.updateAccount(account);
      // Refresh the account list
      await loadAccounts();
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isLoading = false;
    }
  }

  Future<void> deleteAccount(String accountId) async {
    isLoading = true;
    errorMessage = '';
    try {
      await _accountRepository.deleteAccount(accountId);
      // Refresh the account list
      await loadAccounts();
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isLoading = false;
    }
  }

  void clearAccounts() {
    _accounts.clear();
  }
}