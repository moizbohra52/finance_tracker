import 'package:decimal/decimal.dart';

enum AccountType { cash, bank, upi, card, other }

class Account {
  final String id;
  final String userId;
  final String name;
  final AccountType type;
  final Decimal openingBalance;
  final DateTime? openingBalanceDate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Account({
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

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      type: AccountType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => AccountType.other,
      ),
      openingBalance: Decimal.parse(json['opening_balance'].toString()),
      openingBalanceDate: json['opening_balance_date'] != null
          ? DateTime.parse(json['opening_balance_date'] as String)
          : null,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'type': type.toString().split('.').last,
      'opening_balance': openingBalance.toString(),
      'opening_balance_date':
          openingBalanceDate?.toIso8601String().split('T').first,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  Account copyWith({
    String? id,
    String? userId,
    String? name,
    AccountType? type,
    Decimal? openingBalance,
    DateTime? openingBalanceDate,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Account(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      openingBalance: openingBalance ?? this.openingBalance,
      openingBalanceDate: openingBalanceDate ?? this.openingBalanceDate,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}