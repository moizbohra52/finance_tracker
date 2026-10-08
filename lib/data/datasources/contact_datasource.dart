import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/contact.dart';
import 'package:finance_tracker/data/models/contact_transaction.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:sqflite/sqflite.dart';
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

class ContactLocalDatasourceImpl implements ContactDatasource {
  ContactLocalDatasourceImpl(this._db, [this._syncEngine]);

  final AppDatabase _db;
  final SyncEngine? _syncEngine;

  @override
  Future<List<ContactModel>> getContacts() async {
    final List<Map<String, dynamic>> rows = await _db.db.query(
      'contacts',
      where: 'deleted_at IS NULL',
      orderBy: 'name ASC',
    );
    return rows
        .map((Map<String, dynamic> json) => ContactModel.fromJson(json))
        .toList();
  }

  @override
  Future<ContactModel> getContactById(String contactId) async {
    final List<Map<String, dynamic>> rows = await _db.db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: <Object>[contactId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Contact $contactId not found');
    }
    return ContactModel.fromJson(rows.first);
  }

  @override
  Future<void> createContact(ContactModel contact) async {
    final Map<String, dynamic> json = contact.toJson();
    await _db.db.insert('contacts', <String, dynamic>{
      ...json,
      'sync_status': 'pending',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _db.enqueue(
      SyncQueueItem(
        operation: SyncOperation.create,
        entity: 'contacts',
        entityId: contact.id,
        payload: json,
        createdAt: DateTime.now(),
      ),
    );
    _syncEngine?.notifyNewQueueItem();
  }

  @override
  Future<void> updateContact(ContactModel contact) async {
    final Map<String, dynamic> json = contact.toJson();
    await _db.db.update(
      'contacts',
      <String, dynamic>{...json, 'sync_status': 'pending'},
      where: 'id = ?',
      whereArgs: <Object>[contact.id],
    );
    await _db.enqueue(
      SyncQueueItem(
        operation: SyncOperation.update,
        entity: 'contacts',
        entityId: contact.id,
        payload: json,
        createdAt: DateTime.now(),
      ),
    );
    _syncEngine?.notifyNewQueueItem();
  }

  @override
  Future<void> deleteContact(String contactId) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    await _db.db.update(
      'contacts',
      <String, dynamic>{'deleted_at': now, 'sync_status': 'pending'},
      where: 'id = ?',
      whereArgs: <Object>[contactId],
    );
    await _db.enqueue(
      SyncQueueItem(
        operation: SyncOperation.delete,
        entity: 'contacts',
        entityId: contactId,
        payload: tombstone(),
        createdAt: DateTime.now(),
      ),
    );
    _syncEngine?.notifyNewQueueItem();
  }

  @override
  Future<List<ContactTransactionModel>> getContactTransactions(
    String contactId,
  ) async {
    final List<Map<String, dynamic>> rows = await _db.db.query(
      'contact_transactions',
      where: 'contact_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[contactId],
      orderBy: 'transaction_date DESC',
    );
    return rows
        .map(
          (Map<String, dynamic> json) => ContactTransactionModel.fromJson(json),
        )
        .toList();
  }

  @override
  Future<List<ContactTransactionModel>> getAllContactTransactions() async {
    final List<Map<String, dynamic>> rows = await _db.db.query(
      'contact_transactions',
      where: 'deleted_at IS NULL',
      orderBy: 'transaction_date DESC',
    );
    return rows
        .map(
          (Map<String, dynamic> json) => ContactTransactionModel.fromJson(json),
        )
        .toList();
  }

  @override
  Future<void> createContactTransaction(
    ContactTransactionModel transaction,
  ) async {
    final Map<String, dynamic> json = transaction.toJson();
    await _db.db.insert('contact_transactions', <String, dynamic>{
      ...json,
      'sync_status': 'pending',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _db.enqueue(
      SyncQueueItem(
        operation: SyncOperation.create,
        entity: 'contact_transactions',
        entityId: transaction.id,
        payload: json,
        createdAt: DateTime.now(),
      ),
    );
    _syncEngine?.notifyNewQueueItem();
  }

  @override
  Future<void> updateContactTransaction(
    ContactTransactionModel transaction,
  ) async {
    final Map<String, dynamic> json = transaction.toJson();
    await _db.db.update(
      'contact_transactions',
      <String, dynamic>{...json, 'sync_status': 'pending'},
      where: 'id = ?',
      whereArgs: <Object>[transaction.id],
    );
    await _db.enqueue(
      SyncQueueItem(
        operation: SyncOperation.update,
        entity: 'contact_transactions',
        entityId: transaction.id,
        payload: json,
        createdAt: DateTime.now(),
      ),
    );
    _syncEngine?.notifyNewQueueItem();
  }

  @override
  Future<void> deleteContactTransaction(String transactionId) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    await _db.db.update(
      'contact_transactions',
      <String, dynamic>{'deleted_at': now, 'sync_status': 'pending'},
      where: 'id = ?',
      whereArgs: <Object>[transactionId],
    );
    await _db.enqueue(
      SyncQueueItem(
        operation: SyncOperation.delete,
        entity: 'contact_transactions',
        entityId: transactionId,
        payload: tombstone(),
        createdAt: DateTime.now(),
      ),
    );
    _syncEngine?.notifyNewQueueItem();
  }
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
