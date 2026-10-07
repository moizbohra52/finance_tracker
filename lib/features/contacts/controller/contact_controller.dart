import 'package:decimal/decimal.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:get/get.dart';

class ContactController extends GetxController {
  final ContactRepository _contactRepository;

  ContactController(this._contactRepository);

  // Observable lists
  final RxList<Contact> _contacts = <Contact>[].obs;
  List<Contact> get contacts => _contacts;

  // Selected contact
  final Rx<Contact?> _selectedContact = Rx<Contact?>(null);
  Contact? get selectedContact => _selectedContact.value;
  set selectedContact(Contact? value) => _selectedContact.value = value;

  // Loading states
  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;
  set isLoading(bool value) => _isLoading.value = value;

  // Search and filtering
  final RxString _searchQuery = ''.obs;
  String get searchQuery => _searchQuery.value;
  set searchQuery(String value) => _searchQuery.value = value;

  final RxString _filterType = 'all'.obs; // 'all', 'receivable', 'payable'
  String get filterType => _filterType.value;
  set filterType(String value) => _filterType.value = value;

  // Contact transactions
  final RxList<ContactTransaction> _contactTransactions = <ContactTransaction>[].obs;
  List<ContactTransaction> get contactTransactions => _contactTransactions;
  set contactTransactions(List<ContactTransaction> value) => _contactTransactions.value = value;

  // Error handling
  final RxString _errorMessage = ''.obs;
  String get errorMessage => _errorMessage.value;
  set errorMessage(String value) => _errorMessage.value = value;

  @override
  void onInit() {
    super.onInit();
    loadContacts();
  }

  Future<void> loadContacts() async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      final contacts = await _contactRepository.getContacts();
      // Apply search and filtering
      final filteredContacts = contacts.where((contact) {
        // Search filter
        if (_searchQuery.value.isNotEmpty) {
          final searchLower = _searchQuery.value.toLowerCase();
          final matchesSearch = contact.name.toLowerCase().contains(searchLower) ||
              (contact.mobile != null && contact.mobile!.toLowerCase().contains(searchLower)) ||
              (contact.email != null && contact.email!.toLowerCase().contains(searchLower)) ||
              (contact.address != null && contact.address!.toLowerCase().contains(searchLower)) ||
              (contact.notes != null && contact.notes!.toLowerCase().contains(searchLower));
          if (!matchesSearch) return false;
        }

        // Type filter
        if (_filterType.value != 'all') {
          if (_filterType.value == 'receivable' && contact.openingBalanceType != 'receivable') {
            return false;
          }
          if (_filterType.value == 'payable' && contact.openingBalanceType != 'payable') {
            return false;
          }
        }

        return true;
      }).toList();

      _contacts.assignAll(filteredContacts);
    } catch (e) {
      _errorMessage.value = e.toString();
    } finally {
      _isLoading.value = false;
    }
  }

  Future<Contact> getContactById(String contactId) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      final contact = await _contactRepository.getContactById(contactId);
      _selectedContact.value = contact;
      return contact;
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> createContact(Contact contact) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      await _contactRepository.createContact(contact);
      // Optionally refresh the contact list
      await loadContacts();
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> updateContact(Contact contact) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      await _contactRepository.updateContact(contact);
      // Optionally refresh the contact list
      await loadContacts();
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> deleteContact(String contactId) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      await _contactRepository.deleteContact(contactId);
      // Optionally refresh the contact list
      await loadContacts();
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  // Contact Transactions
  Future<List<ContactTransaction>> getContactTransactions(
      String contactId) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      return await _contactRepository.getContactTransactions(contactId);
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> createContactTransaction(
      ContactTransaction transaction) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      await _contactRepository.createContactTransaction(transaction);
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> updateContactTransaction(
      ContactTransaction transaction) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      await _contactRepository.updateContactTransaction(transaction);
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> deleteContactTransaction(String transactionId) async {
    _isLoading.value = true;
    _errorMessage.value = '';
    try {
      await _contactRepository.deleteContactTransaction(transactionId);
    } catch (e) {
      _errorMessage.value = e.toString();
      rethrow;
    } finally {
      _isLoading.value = false;
    }
  }

  // Helper method to calculate balance for a contact
  Future<Decimal> calculateContactBalance(
      String contactId, List<ContactTransaction> transactions) async {
    final contact = await getContactById(contactId);
    return contact.getCurrentBalance(transactions);
  }

  // Check for contacts that need reminders (overdue receivables or payables due soon)
  Future<List<Contact>> checkForReminders() async {
    final contacts = await _contactRepository.getContacts();
    final reminders = <Contact>[];

    for (final contact in contacts) {
      // Skip if contact is deleted
      if (contact.deletedAt != null) continue;

      // Get transactions for this contact
      final transactions = await _contactRepository.getContactTransactions(contact.id);

      // Calculate current balance
      final balance = contact.getCurrentBalance(transactions);

      // Check for overdue receivables (positive balance that should have been collected)
      // For simplicity, we'll consider any receivable balance as needing a reminder
      // In a real app, you'd check due dates or aging
      if (balance > Decimal.zero) {
        reminders.add(contact);
      }
      // Check for payables that need attention (negative balance)
      // Again, for simplicity, we'll consider any payable balance
      else if (balance < Decimal.zero) {
        reminders.add(contact);
      }
    }

    return reminders;
  }

  // Get count of contacts that need reminders
  Future<int> getRemindersCount() async {
    final reminders = await checkForReminders();
    return reminders.length;
  }

  void clearContacts() {
    _contacts.clear();
  }
}