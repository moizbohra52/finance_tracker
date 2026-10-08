import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/account.dart';

class AccountModel {
  final String id;
  final String userId;
  final String name;
  final String type; // Stored as string, will convert to AccountType enum
  final Decimal openingBalance;
  final String? openingBalanceDate; // Stored as YYYY-MM-DD
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  AccountModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.openingBalance,
    this.openingBalanceDate,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory AccountModel.fromJson(Map<String, dynamic> json) => AccountModel(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    name: json['name'] as String,
    type: json['type'] as String,
    openingBalance: Decimal.parse(json['opening_balance'].toString()),
    openingBalanceDate: json['opening_balance_date'] as String?,
    isActive: json['is_active'] == true || json['is_active'] == 1,
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
    'opening_balance': openingBalance.toString(),
    'opening_balance_date': openingBalanceDate,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  Account toEntity() => Account(
    id: id,
    userId: userId,
    name: name,
    type: AccountType.values.firstWhere(
      (e) => e.toString().split('.').last == type,
      orElse: () => AccountType.other,
    ),
    openingBalance: openingBalance,
    openingBalanceDate: openingBalanceDate != null
        ? DateTime.parse(openingBalanceDate!)
        : null,
    isActive: isActive,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  static AccountModel fromEntity(Account account) => AccountModel(
    id: account.id,
    userId: account.userId,
    name: account.name,
    type: account.type.toString().split('.').last,
    openingBalance: account.openingBalance,
    openingBalanceDate: account.openingBalanceDate
        ?.toIso8601String()
        .split('T')
        .first,
    isActive: account.isActive,
    createdAt: account.createdAt,
    updatedAt: account.updatedAt,
    deletedAt: account.deletedAt,
  );
}
