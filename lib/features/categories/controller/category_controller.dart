import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:get/get.dart';

class CategoryController extends GetxController {
  final CategoryRepository _categoryRepository;

  CategoryController(this._categoryRepository);

  // Observable lists
  final RxList<Category> _categories = <Category>[].obs;
  List<Category> get categories => _categories;

  // Loading states
  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;
  set isLoading(bool value) => _isLoading.value = value;

  // Error handling
  final RxString _errorMessage = ''.obs;
  String get errorMessage => _errorMessage.value;
  set errorMessage(String value) => _errorMessage.value = value;

  @override
  void onInit() {
    super.onInit();
    loadCategories();
  }

  Future<void> loadCategories() async {
    isLoading = true;
    errorMessage = '';
    try {
      final categories = await _categoryRepository.getCategories();
      _categories.assignAll(categories);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  Future<Category> getCategoryById(String categoryId) async {
    isLoading = true;
    errorMessage = '';
    try {
      final category = await _categoryRepository.getCategoryById(categoryId);
      return category;
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isLoading = false;
    }
  }

  Future<void> createCategory(Category category) async {
    isLoading = true;
    errorMessage = '';
    try {
      await _categoryRepository.createCategory(category);
      // Refresh the category list
      await loadCategories();
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isLoading = false;
    }
  }

  Future<void> updateCategory(Category category) async {
    isLoading = true;
    errorMessage = '';
    try {
      await _categoryRepository.updateCategory(category);
      // Refresh the category list
      await loadCategories();
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isLoading = false;
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    isLoading = true;
    errorMessage = '';
    try {
      await _categoryRepository.deleteCategory(categoryId);
      // Refresh the category list
      await loadCategories();
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isLoading = false;
    }
  }

  void clearCategories() {
    _categories.clear();
  }
}
