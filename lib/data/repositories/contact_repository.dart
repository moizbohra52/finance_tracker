import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/datasources/contact_datasource.dart';
import 'package:finance_tracker/data/models/contact.dart';
import 'package:finance_tracker/data/models/contact_transaction.dart';
import 'package:finance_tracker/domain/entities/contact.dart';

class ContactRepository {
  final ContactDatasource _contactDatasource;

  ContactRepository(this._contactDatasource);

  Future<List<Contact>> getContacts() async {
    return guardSupabase(() async {
      final contactModels = await _contactDatasource.getContacts();
      return contactModels.map((model) => model.toEntity()).toList();
    });
  }

  Future<Contact> getContactById(String contactId) async {
    return guardSupabase(() async {
      final contactModel = await _contactDatasource.getContactById(contactId);
      return contactModel.toEntity();
    });
  }

  Future<void> createContact(Contact contact) async {
    return guardSupabase(() async {
      final contactModel = ContactModel.fromEntity(contact);
      await _contactDatasource.createContact(contactModel);
    });
  }

  Future<void> updateContact(Contact contact) async {
    return guardSupabase(() async {
      final contactModel = ContactModel.fromEntity(contact);
      await _contactDatasource.updateContact(contactModel);
    });
  }

  Future<void> deleteContact(String contactId) async {
    return guardSupabase(() async {
      await _contactDatasource.deleteContact(contactId);
    });
  }

  // Contact Transactions
  Future<List<ContactTransaction>> getContactTransactions(
    String contactId,
  ) async {
    return guardSupabase(() async {
      final transactionModels = await _contactDatasource.getContactTransactions(
        contactId,
      );
      return transactionModels.map((model) => model.toEntity()).toList();
    });
  }

  Future<List<ContactTransaction>> getAllContactTransactions() async {
    return guardSupabase(() async {
      final models = await _contactDatasource.getAllContactTransactions();
      return models.map((model) => model.toEntity()).toList();
    });
  }

  Future<void> createContactTransaction(ContactTransaction transaction) async {
    return guardSupabase(() async {
      final transactionModel = ContactTransactionModel.fromEntity(transaction);
      await _contactDatasource.createContactTransaction(transactionModel);
    });
  }

  Future<void> updateContactTransaction(ContactTransaction transaction) async {
    return guardSupabase(() async {
      final transactionModel = ContactTransactionModel.fromEntity(transaction);
      await _contactDatasource.updateContactTransaction(transactionModel);
    });
  }

  Future<void> deleteContactTransaction(String transactionId) async {
    return guardSupabase(() async {
      await _contactDatasource.deleteContactTransaction(transactionId);
    });
  }
}
