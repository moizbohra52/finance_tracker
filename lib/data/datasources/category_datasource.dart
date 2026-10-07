import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/data/models/category.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class CategoryDatasource {
  Future<List<Category>> getCategories();
  Future<Category> getCategoryById(String categoryId);
  Future<void> createCategory(Category category);
  Future<void> updateCategory(Category category);
  Future<void> deleteCategory(String categoryId);
}

class CategoryDatasourceImpl implements CategoryDatasource {
  CategoryDatasourceImpl(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  @override
  Future<List<Category>> getCategories() async {
    final raw = await _supabaseClient.from('categories').select();
    return raw.map((json) => CategoryModel.fromJson(json).toEntity()).toList();
  }

  @override
  Future<Category> getCategoryById(String categoryId) async {
    final response = await _supabaseClient
        .from('categories')
        .select()
        .eq('id', categoryId)
        .single();
    return CategoryModel.fromJson(response).toEntity();
  }

  @override
  Future<void> createCategory(Category category) async {
    final response = await _supabaseClient
        .from('categories')
        .insert(CategoryModel.fromEntity(category).toJson());
  }

  @override
  Future<void> updateCategory(Category category) async {
    await _supabaseClient
        .from('categories')
        .update(CategoryModel.fromEntity(category).toJson())
        .eq('id', category.id);
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    await _supabaseClient.from('categories').delete().eq('id', categoryId);
  }
}
