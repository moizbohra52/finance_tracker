import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// Arguments for the add or edit credit/debit route.
class ContactEntryArgs {
  const ContactEntryArgs({
    required this.contactId,
    required this.type,
    this.contactName,
    this.existing,
  });

  final String contactId;
  final ContactTransactionType type;
  final String? contactName;
  final ContactTransaction? existing;
}

/// Saves a contact (create or edit) or one ledger entry for a contact.
class ContactFormController extends GetxController {
  ContactFormController(this._repository, this._notifier);

  final ContactRepository _repository;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final SubmitState save = SubmitState();

  /// [id] is generated once per form so a retried save upserts one row.
  Future<bool> saveContact({
    required String id,
    Contact? existing,
    required String name,
    required String? mobile,
    required String? email,
    required String? address,
    required String? notes,
    required Decimal openingBalance,
    required String openingBalanceType,
  }) => save.run(() async {
    final DateTime now = DateTime.now();
    final Contact contact = Contact(
      id: id,
      userId: existing?.userId ?? '',
      name: name,
      mobile: mobile,
      email: email,
      address: address,
      notes: notes,
      openingBalance: openingBalance,
      openingBalanceType: openingBalanceType,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (existing == null) {
      await _repository.createContact(contact);
    } else {
      await _repository.updateContact(contact);
    }
    _notifier.markChanged();
  });

  Future<bool> saveEntry({
    required String id,
    ContactTransaction? existing,
    required String contactId,
    required ContactTransactionType type,
    required Decimal amount,
    required DateTime date,
    required DateTime? dueDate,
    required String? note,
  }) => save.run(() async {
    final DateTime now = DateTime.now();
    final ContactTransaction transaction = ContactTransaction(
      id: id,
      userId: existing?.userId ?? '',
      contactId: contactId,
      type: type,
      amount: amount,
      transactionDate: date,
      dueDate: dueDate,
      note: note,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (existing == null) {
      await _repository.createContactTransaction(transaction);
    } else {
      await _repository.updateContactTransaction(transaction);
    }
    _notifier.markChanged();
  });

  static String newId() => _uuid.v4();
}
