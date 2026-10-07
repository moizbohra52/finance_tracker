import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';

class TransactionModel {
  final String id;
  final String userId;
  final String accountId;
  final String? categoryId;
  final String? contactId;
  final String type; // Stored as string, will convert to TransactionType enum
  final String amount; // Stored as string to preserve precision
  final String transactionDate;
  final String? note;
  final String? description;
  final String? paymentMethod;
  final String? transferId;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  TransactionModel({
    required this.id,
    required this.userId,
    required this.accountId,
    this.categoryId,
    this.contactId,
    required this.type,
    required this.amount,
    required this.transactionDate,
    this.note,
    this.description,
    this.paymentMethod,
    this.transferId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      TransactionModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        accountId: json['account_id'] as String,
        categoryId: json['category_id'] as String?,
        contactId: json['contact_id'] as String?,
        type: json['type'] as String,
        amount: json['amount'].toString(),
        transactionDate: json['transaction_date'] as String,
        note: json['note'] as String?,
        description: json['description'] as String?,
        paymentMethod: json['payment_method'] as String?,
        transferId: json['transfer_id'] as String?,
        createdAt: json['created_at'] as String,
        updatedAt: json['updated_at'] as String,
        deletedAt: json['deleted_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'account_id': accountId,
    'category_id': categoryId,
    'contact_id': contactId,
    'type': type,
    'amount': amount,
    'transaction_date': transactionDate,
    'note': note,
    'description': description,
    'payment_method': paymentMethod,
    'transfer_id': transferId,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };

  Transaction toEntity() => Transaction(
    id: id,
    userId: userId,
    accountId: accountId,
    categoryId: categoryId,
    contactId: contactId,
    type: _parseTransactionType(type),
    amount: Decimal.parse(amount),
    transactionDate: DateTime.parse(transactionDate).toLocal(),
    note: note,
    description: description,
    paymentMethod: paymentMethod,
    transferId: transferId,
    createdAt: DateTime.parse(createdAt),
    updatedAt: DateTime.parse(updatedAt),
    deletedAt: deletedAt != null ? DateTime.parse(deletedAt!) : null,
  );

  static TransactionModel fromEntity(Transaction transaction) =>
      TransactionModel(
        id: transaction.id,
        userId: transaction.userId,
        accountId: transaction.accountId,
        categoryId: transaction.categoryId,
        contactId: transaction.contactId,
        type: _transactionTypeToString(transaction.type),
        amount: transaction.amount.toString(),
        transactionDate: transaction.transactionDate.toUtc().toIso8601String(),
        note: transaction.note,
        description: transaction.description,
        paymentMethod: transaction.paymentMethod,
        transferId: transaction.transferId,
        createdAt: transaction.createdAt.toIso8601String(),
        updatedAt: transaction.updatedAt.toIso8601String(),
        deletedAt: transaction.deletedAt?.toIso8601String(),
      );

  static TransactionType _parseTransactionType(String type) {
    switch (type) {
      case 'income':
        return TransactionType.income;
      case 'expense':
        return TransactionType.expense;
      case 'transfer_in':
        return TransactionType.transfer_in;
      case 'transfer_out':
        return TransactionType.transfer_out;
      case 'adjustment_in':
        return TransactionType.adjustment_in;
      case 'adjustment_out':
        return TransactionType.adjustment_out;
      case 'opening_balance':
        return TransactionType.opening_balance;
      case 'payment_received':
        return TransactionType.payment_received;
      case 'payment_made':
        return TransactionType.payment_made;
      default:
        throw ArgumentError('Unknown transaction type: $type');
    }
  }

  static String _transactionTypeToString(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'income';
      case TransactionType.expense:
        return 'expense';
      case TransactionType.transfer_in:
        return 'transfer_in';
      case TransactionType.transfer_out:
        return 'transfer_out';
      case TransactionType.adjustment_in:
        return 'adjustment_in';
      case TransactionType.adjustment_out:
        return 'adjustment_out';
      case TransactionType.opening_balance:
        return 'opening_balance';
      case TransactionType.payment_received:
        return 'payment_received';
      case TransactionType.payment_made:
        return 'payment_made';
    }
  }
}
