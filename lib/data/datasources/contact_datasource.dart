import 'package:finance_tracker/data/models/contact.dart';
import 'package:finance_tracker/data/models/contact_transaction.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ContactDatasource {
  Future<List<ContactModel>> getContacts();
  Future<ContactModel> getContactById(String contactId);
  Future<void> createContact(ContactModel contact);
  Future<void> updateContact(ContactModel contact);
  Future<void> deleteContact(String contactId);

  // Contact Transactions
  Future<List<ContactTransactionModel>> getContactTransactions(
    String contactId,
  );
  Future<List<ContactTransactionModel>> getAllContactTransactions();
  Future<void> createContactTransaction(ContactTransactionModel transaction);
  Future<void> updateContactTransaction(ContactTransactionModel transaction);
  Future<void> deleteContactTransaction(String transactionId);
}

class ContactDatasourceImpl implements ContactDatasource {
  ContactDatasourceImpl(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  @override
  Future<List<ContactModel>> getContacts() async {
    final response = await _supabaseClient
        .from('contacts')
        .select()
        .isFilter('deleted_at', null)
        .order('name');

    final List<dynamic> raw = response as List<dynamic>;
    final List<Map<String, dynamic>> data = raw
        .map((e) => e as Map<String, dynamic>)
        .toList();
    return data.map((json) => ContactModel.fromJson(json)).toList();
  }

  @override
  Future<ContactModel> getContactById(String contactId) async {
    final response = await _supabaseClient
        .from('contacts')
        .select('*')
        .eq('id', contactId)
        .single();

    return ContactModel.fromJson(response);
  }

  @override
  Future<void> createContact(ContactModel contact) async {
    await _supabaseClient
        .from('contacts')
        .upsert(insertPayload(_supabaseClient, contact.toJson()));
  }

  @override
  Future<void> updateContact(ContactModel contact) async {
    await _supabaseClient
        .from('contacts')
        .update(updatePayload(contact.toJson()))
        .eq('id', contact.id);
  }

  @override
  Future<void> deleteContact(String contactId) async {
    await _supabaseClient
        .from('contacts')
        .update(tombstone())
        .eq('id', contactId);
  }

  // Contact Transactions
  @override
  Future<List<ContactTransactionModel>> getContactTransactions(
    String contactId,
  ) async {
    final response = await _supabaseClient
        .from('contact_transactions')
        .select()
        .eq('contact_id', contactId)
        .isFilter('deleted_at', null)
        .order('transaction_date', ascending: false);

    final List<dynamic> raw = response as List<dynamic>;
    final List<Map<String, dynamic>> data = raw
        .map((e) => e as Map<String, dynamic>)
        .toList();
    return data.map((json) => ContactTransactionModel.fromJson(json)).toList();
  }

  @override
  Future<List<ContactTransactionModel>> getAllContactTransactions() async {
    final response = await _supabaseClient
        .from('contact_transactions')
        .select()
        .isFilter('deleted_at', null)
        .order('transaction_date', ascending: false);
    final List<dynamic> raw = response as List<dynamic>;
    return raw
        .map((e) => ContactTransactionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createContactTransaction(
    ContactTransactionModel transaction,
  ) async {
    await _supabaseClient
        .from('contact_transactions')
        .upsert(insertPayload(_supabaseClient, transaction.toJson()));
  }

  @override
  Future<void> updateContactTransaction(
    ContactTransactionModel transaction,
  ) async {
    await _supabaseClient
        .from('contact_transactions')
        .update(updatePayload(transaction.toJson()))
        .eq('id', transaction.id);
  }

  @override
  Future<void> deleteContactTransaction(String transactionId) async {
    await _supabaseClient
        .from('contact_transactions')
        .update(tombstone())
        .eq('id', transactionId);
  }
}
