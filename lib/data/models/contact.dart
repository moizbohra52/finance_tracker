import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/contact.dart';

class ContactModel {
  final String id;
  final String userId;
  final String name;
  final String? mobile;
  final String? email;
  final String? address;
  final String? notes;
  final String openingBalance; // Stored as string to preserve precision
  final String openingBalanceType; // 'receivable' or 'payable'
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  ContactModel({
    required this.id,
    required this.userId,
    required this.name,
    this.mobile,
    this.email,
    this.address,
    this.notes,
    required this.openingBalance,
    required this.openingBalanceType,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory ContactModel.fromJson(Map<String, dynamic> json) => ContactModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        name: json['name'] as String,
        mobile: json['mobile'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        notes: json['notes'] as String?,
        openingBalance: json['opening_balance'] as String,
        openingBalanceType: json['opening_balance_type'] as String,
        createdAt: json['created_at'] as String,
        updatedAt: json['updated_at'] as String,
        deletedAt: json['deleted_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'mobile': mobile,
        'email': email,
        'address': address,
        'notes': notes,
        'opening_balance': openingBalance,
        'opening_balance_type': openingBalanceType,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  Contact toEntity() => Contact(
        id: id,
        userId: userId,
        name: name,
        mobile: mobile,
        email: email,
        address: address,
        notes: notes,
        openingBalance: Decimal.parse(openingBalance),
        openingBalanceType: openingBalanceType,
        createdAt: DateTime.parse(createdAt),
        updatedAt: DateTime.parse(updatedAt),
        deletedAt: deletedAt != null ? DateTime.parse(deletedAt!) : null,
      );

  static ContactModel fromEntity(Contact contact) => ContactModel(
        id: contact.id,
        userId: contact.userId,
        name: contact.name,
        mobile: contact.mobile,
        email: contact.email,
        address: contact.address,
        notes: contact.notes,
        openingBalance: contact.openingBalance.toString(),
        openingBalanceType: contact.openingBalanceType,
        createdAt: contact.createdAt.toIso8601String(),
        updatedAt: contact.updatedAt.toIso8601String(),
        deletedAt: contact.deletedAt?.toIso8601String(),
      );
}