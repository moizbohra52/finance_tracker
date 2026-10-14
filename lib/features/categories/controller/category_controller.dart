import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// Arguments for the category form: the kind of category to create, or the
/// category to edit.
class CategoryFormArgs {
  const CategoryFormArgs({this.type = CategoryType.expense, this.existing});

  final CategoryType type;
  final Category? existing;
}

/// Lists the categories and creates, edits and deletes the user's own.
/// Built-in (system) categories are shared by every user and read-only: the
/// database refuses writes to them (RLS, docs/04_SECURITY_RLS.md).
class CategoryController extends GetxController {
  CategoryController(this._repository, this._notifier);

  final CategoryRepository _repository;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final RxList<Category> categories = <Category>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();

  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();

  // GetX does not dispose workers, and the notifier outlives this
  // controller, so without this a closed controller keeps reloading.
  late final Worker _changes;

  @override
  void onInit() {
    super.onInit();
    load();
    _changes = ever<int>(_notifier.version, (_) => load(silent: true));
  }

  @override
  void onClose() {
    _changes.dispose();
    super.onClose();
  }

  /// Reloads the list. A [silent] reload keeps the current list visible.
  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      categories.assignAll(await _repository.getCategories());
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// Categories usable for [type] (including those for both kinds), the
  /// user's own first, then the built-in ones, each by name.
  List<Category> ofType(CategoryType type) {
    final List<Category> rows = categories
        .where((Category c) => c.type == type || c.type == CategoryType.both)
        .toList();
    rows.sort((Category a, Category b) {
      if (a.isSystem != b.isSystem) return a.isSystem ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return rows;
  }

  /// A message when [name] is empty or already used by another category of
  /// the same kind (built-in ones included, ignoring case), else null.
  String? nameError(String name, CategoryType type, {String? exceptId}) {
    final String wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return 'Enter a name';
    final bool taken = categories.any(
      (Category c) =>
          c.id != exceptId &&
          c.name.trim().toLowerCase() == wanted &&
          (c.type == type ||
              c.type == CategoryType.both ||
              type == CategoryType.both),
    );
    return taken ? 'A category with this name already exists' : null;
  }

  /// Creates a category, or updates [existing] (its kind never changes, so
  /// past transactions keep their meaning). [id] is generated once per form,
  /// so a retried save upserts the same row. Returns the category's id, or
  /// null on failure (the message is in [save]).
  Future<String?> saveCategory({
    required String id,
    Category? existing,
    required String name,
    required CategoryType type,
    required String icon,
  }) async {
    final String savedId = existing?.id ?? id;
    final bool ok = await save.run(() async {
      final DateTime now = DateTime.now();
      final Category category = Category(
        id: savedId,
        userId: existing?.userId,
        name: name.trim(),
        type: existing?.type ?? type,
        icon: icon,
        isSystem: false,
        isActive: true,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      if (existing == null) {
        await _repository.createCategory(category);
      } else {
        await _repository.updateCategory(category);
      }
      _notifier.markChanged();
    });
    return ok ? savedId : null;
  }

  /// Deletes one of the user's own categories (a soft delete). Transactions,
  /// budgets and schedules that used it keep their amounts; they just no
  /// longer show its name.
  Future<bool> deleteCategory(Category category) {
    return deletion.run(() async {
      await _repository.deleteCategory(category.id);
      _notifier.markChanged();
    });
  }

  static String newId() => _uuid.v4();
}
