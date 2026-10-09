import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:get/get.dart';

/// A contact with its current khata balance: positive means they owe the
/// user (receivable), negative means the user owes them (payable).
class ContactBalance {
  const ContactBalance(this.contact, this.balance);

  final Contact contact;
  final Decimal balance;

  bool get isReceivable => balance > Decimal.zero;
  bool get isPayable => balance < Decimal.zero;
}

enum KhataFilter { all, receivable, payable }

/// Khata list: contacts with balances, search and a receivable/payable filter.
class ContactController extends GetxController {
  ContactController(this._repository, this._notifier);

  final ContactRepository _repository;
  final DataChangeNotifier _notifier;

  final RxList<ContactBalance> _all = <ContactBalance>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final RxString searchText = ''.obs;
  final Rx<KhataFilter> filter = KhataFilter.all.obs;
  final Rx<KhataSummary> summary = KhataSummary.zero.obs;

  /// Contacts matching the current search and filter.
  List<ContactBalance> get visible {
    final String query = searchText.value.trim().toLowerCase();
    return _all.where((ContactBalance row) {
      final bool matchesFilter = switch (filter.value) {
        KhataFilter.all => true,
        KhataFilter.receivable => row.isReceivable,
        KhataFilter.payable => row.isPayable,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      final Contact c = row.contact;
      return c.name.toLowerCase().contains(query) ||
          (c.mobile ?? '').toLowerCase().contains(query);
    }).toList();
  }

  bool get hasContacts => _all.isNotEmpty;

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
    load();
    _changes = ever<int>(_notifier.version, (_) => load(silent: true));
  }

  // ponytail: contacts and their ledger rows are loaded in full and searched
  // in memory; add server paging if a user ever holds thousands of contacts.
  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final (
        List<Contact> contacts,
        List<ContactTransaction> entries,
      ) = await wait2(
        _repository.getContacts(),
        _repository.getAllContactTransactions(),
      );
      final Map<String, List<ContactTransaction>> byContact =
          <String, List<ContactTransaction>>{};
      for (final ContactTransaction t in entries) {
        byContact.putIfAbsent(t.contactId, () => <ContactTransaction>[]).add(t);
      }
      _all.assignAll(
        contacts.map(
          (Contact c) => ContactBalance(
            c,
            c.getCurrentBalance(
              byContact[c.id] ?? const <ContactTransaction>[],
            ),
          ),
        ),
      );
      summary.value = FinanceSummaryCalculator.khata(contacts, entries);
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }
}
