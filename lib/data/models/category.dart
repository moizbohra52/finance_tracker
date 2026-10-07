import 'package:finance_tracker/domain/entities/category.dart';

class CategoryModel {
  final String id;
  final String? userId;
  final String name;
  final String type; // Stored as string, will convert to CategoryType enum
  final String icon;
  final bool isSystem;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  CategoryModel({
    required this.id,
    this.userId,
    required this.name,
    required this.type,
    required this.icon,
    required this.isSystem,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
    id: json['id'] as String,
    userId: json['user_id'] as String?,
    name: json['name'] as String,
    type: json['type'] as String,
    icon: (json['icon'] as String?) ?? 'other',
    isSystem: json['is_system'] as bool,
    isActive: json['is_active'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    deletedAt: json['deleted_at'] != null
        ? DateTime.parse(json['deleted_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'type': type,
    'icon': icon,
    'is_system': isSystem,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  Category toEntity() => Category(
    id: id,
    userId: userId,
    name: name,
    type: CategoryType.values.firstWhere(
      (e) => _categoryTypeToString(e) == type,
    ),
    icon: icon,
    isSystem: isSystem,
    isActive: isActive,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  static CategoryModel fromEntity(Category category) => CategoryModel(
    id: category.id,
    userId: category.userId,
    name: category.name,
    type: _categoryTypeToString(category.type),
    icon: category.icon,
    isSystem: category.isSystem,
    isActive: category.isActive,
    createdAt: category.createdAt,
    updatedAt: category.updatedAt,
    deletedAt: category.deletedAt,
  );

  static String _categoryTypeToString(CategoryType type) {
    switch (type) {
      case CategoryType.income:
        return 'income';
      case CategoryType.expense:
        return 'expense';
      case CategoryType.both:
        return 'both';
    }
  }
}
