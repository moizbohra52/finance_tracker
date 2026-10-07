import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/contact.dart';

class ContactTransactionModel {
  final String id;
  final String userId;
  final String contactId;
  final String type; // Stored as string, will convert to ContactTransactionType enum
  final String amount; // Stored as string to preserve precision
  final String transactionDate;
  final String? dueDate;
  final String? note;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  ContactTransactionModel({
    required this.id,
    required this.userId,
    required this.contactId,
    required this.type,
    required this.amount,
    required this.transactionDate,
    this.dueDate,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory ContactTransactionModel.fromJson(Map<String, dynamic> json) => ContactTransactionModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        contactId: json['contact_id'] as String,
        type: json['type'] as String,
        amount: json['amount'] as String,
        transactionDate: json['transaction_date'] as String,
        dueDate: json['due_date'] as String?,
        note: json['note'] as String?,
        createdAt: json['created_at'] as String,
        updatedAt: json['updated_at'] as String,
        deletedAt: json['deleted_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'contact_id': contactId,
        'type': type,
        'amount': amount,
        'transaction_date': transactionDate,
        'due_date': dueDate,
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  ContactTransaction toEntity() => ContactTransaction(
        id: id,
        userId: userId,
        contactId: contactId,
        type: _parseContactTransactionType(type),
        amount: Decimal.parse(amount),
        transactionDate: DateTime.parse(transactionDate),
        dueDate: dueDate != null ? DateTime.parse(dueDate!) : null,
        note: note,
        createdAt: DateTime.parse(createdAt),
        updatedAt: DateTime.parse(updatedAt),
        deletedAt: deletedAt != null ? DateTime.parse(deletedAt!) : null,
      );

  static ContactTransactionModel fromEntity(ContactTransaction contactTransaction) => ContactTransactionModel(
        id: contactTransaction.id,
        userId: contactTransaction.userId,
        contactId: contactTransaction.contactId,
        type: _contactTransactionTypeToString(contactTransaction.type),
        amount: contactTransaction.amount.toString(),
        transactionDate: contactTransaction.transactionDate.toIso8601String(),
        dueDate: contactTransaction.dueDate?.toIso8601String(),
        note: contactTransaction.note,
        createdAt: contactTransaction.createdAt.toIso8601String(),
        updatedAt: contactTransaction.updatedAt.toIso8601String(),
        deletedAt: contactTransaction.deletedAt?.toIso8601String(),
      );

  static ContactTransactionType _parseContactTransactionType(String type) {
    switch (type) {
      case 'credit':
        return ContactTransactionType.credit;
      case 'debit':
        return ContactTransactionType.debit;
      case 'payment_received':
        return ContactTransactionType.paymentReceived;
      case 'payment_made':
        return ContactTransactionType.paymentMade;
      case 'adjustment':
        return ContactTransactionType.adjustment;
      default:
        throw ArgumentError('Unknown contact transaction type: $type');
    }
  }

  static String _contactTransactionTypeToString(ContactTransactionType type) {
    switch (type) {
      case ContactTransactionType.credit:
        return 'credit';
      case ContactTransactionType.debit:
        return 'debit';
      case ContactTransactionType.paymentReceived:
        return 'payment_received';
      case ContactTransactionType.paymentMade:
        return 'payment_made';
      case ContactTransactionType.adjustment:
        return 'adjustment';
    }
  }
}