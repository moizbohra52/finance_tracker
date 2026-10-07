import 'package:finance_tracker/data/models/category.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CategoryRepository {
  CategoryRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  Future<List<Category>> getCategories() => guardSupabase(() async {
    final List<Map<String, dynamic>> data = await _supabaseClient
        .from('categories')
        .select()
        .isFilter('deleted_at', null)
        .eq('is_active', true)
        .order('name');
    return data.map((json) => CategoryModel.fromJson(json).toEntity()).toList();
  });

  Future<Category> getCategoryById(String categoryId) async {
    final response = await _supabaseClient
        .from('categories')
        .select()
        .eq('id', categoryId)
        .single();
    return CategoryModel.fromJson(response).toEntity();
  }

  Future<void> createCategory(Category category) async {
    await _supabaseClient
        .from('categories')
        .insert(CategoryModel.fromEntity(category).toJson());
  }

  Future<void> updateCategory(Category category) async {
    await _supabaseClient
        .from('categories')
        .update(CategoryModel.fromEntity(category).toJson())
        .eq('id', category.id);
  }

  Future<void> deleteCategory(String categoryId) async {
    await _supabaseClient.from('categories').delete().eq('id', categoryId);
  }
}
