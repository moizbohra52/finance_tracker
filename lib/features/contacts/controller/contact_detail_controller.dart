import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:get/get.dart';

/// One contact, their ledger entries and current balance.
class ContactDetailController extends GetxController {
  ContactDetailController(this._repository, this._notifier, this.contactId);

  final ContactRepository _repository;
  final DataChangeNotifier _notifier;
  final String contactId;

  final Rxn<Contact> contact = Rxn<Contact>();
  final RxList<ContactTransaction> entries = <ContactTransaction>[].obs;
  final Rx<Decimal> balance = Decimal.zero.obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final SubmitState deletion = SubmitState();

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

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final (Contact loaded, List<ContactTransaction> list) = await wait2(
        _repository.getContactById(contactId),
        _repository.getContactTransactions(contactId),
      );
      contact.value = loaded.deletedAt == null ? loaded : null;
      entries.assignAll(list);
      balance.value = loaded.getCurrentBalance(list);
    } on AppException catch (failure) {
      if (!silent) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> deleteContact() => deletion.run(() async {
    await _repository.deleteContact(contactId);
    _notifier.markChanged();
  });

  Future<bool> deleteEntry(String entryId) => deletion.run(() async {
    await _repository.deleteContactTransaction(entryId);
    _notifier.markChanged();
  });
}
