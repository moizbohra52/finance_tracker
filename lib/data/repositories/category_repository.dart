import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/category.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CategoryRepository {
  CategoryRepository(
    this._supabaseClient, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _syncEngine = syncEngine;

  final SupabaseClient _supabaseClient;
  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  Future<List<Category>> getCategories() async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'categories',
        where: 'deleted_at IS NULL AND is_active = 1',
        orderBy: 'name ASC',
      );
      return data
          .map(
            (Map<String, dynamic> json) =>
                CategoryModel.fromJson(json).toEntity(),
          )
          .toList();
    }

    return guardSupabase(() async {
      final List<Map<String, dynamic>> data = await _supabaseClient
          .from('categories')
          .select()
          .isFilter('deleted_at', null)
          .eq('is_active', true)
          .order('name');
      return data
          .map(
            (Map<String, dynamic> json) =>
                CategoryModel.fromJson(json).toEntity(),
          )
          .toList();
    });
  }

  Future<Category> getCategoryById(String categoryId) async {
    if (_db != null) {
      final List<Map<String, dynamic>> data = await _db.db.query(
        'categories',
        where: 'id = ?',
        whereArgs: <Object>[categoryId],
        limit: 1,
      );
      if (data.isNotEmpty) {
        return CategoryModel.fromJson(data.first).toEntity();
      }
    }

    final response = await _supabaseClient
        .from('categories')
        .select()
        .eq('id', categoryId)
        .single();
    return CategoryModel.fromJson(response).toEntity();
  }

  Future<void> createCategory(Category category) async {
    if (_db != null) {
      final CategoryModel model = CategoryModel.fromEntity(category);
      final Map<String, dynamic> json = model.toJson();
      await _db.db.insert('categories', <String, dynamic>{
        ...json,
        'is_system': category.isSystem ? 1 : 0,
        'is_active': category.isActive ? 1 : 0,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.create,
          entity: 'categories',
          entityId: category.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await _supabaseClient
        .from('categories')
        .insert(CategoryModel.fromEntity(category).toJson());
  }

  Future<void> updateCategory(Category category) async {
    if (_db != null) {
      final CategoryModel model = CategoryModel.fromEntity(category);
      final Map<String, dynamic> json = model.toJson();
      await _db.db.update(
        'categories',
        <String, dynamic>{
          ...json,
          'is_system': category.isSystem ? 1 : 0,
          'is_active': category.isActive ? 1 : 0,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: <Object>[category.id],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.update,
          entity: 'categories',
          entityId: category.id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await _supabaseClient
        .from('categories')
        .update(CategoryModel.fromEntity(category).toJson())
        .eq('id', category.id);
  }

  Future<void> deleteCategory(String categoryId) async {
    if (_db != null) {
      final String now = DateTime.now().toUtc().toIso8601String();
      await _db.db.update(
        'categories',
        <String, dynamic>{'deleted_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object>[categoryId],
      );
      await _db.enqueue(
        SyncQueueItem(
          operation: SyncOperation.delete,
          entity: 'categories',
          entityId: categoryId,
          payload: tombstone(),
          createdAt: DateTime.now(),
        ),
      );
      _syncEngine?.notifyNewQueueItem();
      return;
    }

    await _supabaseClient.from('categories').delete().eq('id', categoryId);
  }
}
