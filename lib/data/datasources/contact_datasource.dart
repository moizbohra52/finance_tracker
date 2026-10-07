import 'package:finance_tracker/data/models/contact.dart';
import 'package:finance_tracker/data/models/contact_transaction.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ContactDatasource {
  Future<List<ContactModel>> getContacts();
  Future<ContactModel> getContactById(String contactId);
  Future<void> createContact(ContactModel contact);
  Future<void> updateContact(ContactModel contact);
  Future<void> deleteContact(String contactId);

  // Contact Transactions
  Future<List<ContactTransactionModel>> getContactTransactions(String contactId);
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
        .order('created_at', ascending: false);

    final List<dynamic> raw = response as List<dynamic>;
    final List<Map<String, dynamic>> data =
        raw.map((e) => e as Map<String, dynamic>).toList();
    return data
        .map((json) => ContactModel.fromJson(json))
        .toList();
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
        .insert(contact.toJson());
  }

  @override
  Future<void> updateContact(ContactModel contact) async {
    await _supabaseClient
        .from('contacts')
        .update(contact.toJson())
        .eq('id', contact.id);
  }

  @override
  Future<void> deleteContact(String contactId) async {
    await _supabaseClient
        .from('contacts')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', contactId);
  }

  // Contact Transactions
  @override
  Future<List<ContactTransactionModel>> getContactTransactions(String contactId) async {
    final response = await _supabaseClient
        .from('contact_transactions')
        .select()
        .eq('contact_id', contactId)
        .order('transaction_date', ascending: false);

    final List<dynamic> raw = response as List<dynamic>;
    final List<Map<String, dynamic>> data =
        raw.map((e) => e as Map<String, dynamic>).toList();
    return data
        .map((json) => ContactTransactionModel.fromJson(json))
        .toList();
  }

  @override
  Future<void> createContactTransaction(ContactTransactionModel transaction) async {
    await _supabaseClient
        .from('contact_transactions')
        .insert(transaction.toJson());
  }

  @override
  Future<void> updateContactTransaction(ContactTransactionModel transaction) async {
    await _supabaseClient
        .from('contact_transactions')
        .update(transaction.toJson())
        .eq('id', transaction.id);
  }

  @override
  Future<void> deleteContactTransaction(String transactionId) async {
    await _supabaseClient
        .from('contact_transactions')
        .delete()
        .eq('id', transactionId);
  }
}