// ignore_for_file: constant_identifier_names
import 'package:decimal/decimal.dart';

enum TransactionType {
  income,
  expense,
  transfer_in,
  transfer_out,
  adjustment_in,
  adjustment_out,
  opening_balance,
  payment_received,
  payment_made,
}

class Transaction {
  final String id;
  final String userId;
  final String accountId;
  final String? categoryId;
  final String? contactId;
  final TransactionType type;
  final Decimal amount;
  final DateTime transactionDate;
  final String? note;
  final String? description;
  final String? paymentMethod;
  final String? transferId; // shared by both legs of a transfer
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Transaction({
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

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      accountId: json['account_id'] as String,
      categoryId: json['category_id'] as String?,
      contactId: json['contact_id'] as String?,
      type: _parseTransactionType(json['type'] as String),
      amount: Decimal.parse(json['amount'].toString()),
      transactionDate: DateTime.parse(json['transaction_date'] as String),
      note: json['note'] as String?,
      description: json['description'] as String?,
      paymentMethod: json['payment_method'] as String?,
      transferId: json['transfer_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'account_id': accountId,
      'category_id': categoryId,
      'contact_id': contactId,
      'type': _transactionTypeToString(type),
      'amount': amount.toString(),
      'transaction_date': transactionDate.toIso8601String(),
      'note': note,
      'description': description,
      'payment_method': paymentMethod,
      'transfer_id': transferId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
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

  Transaction copyWith({
    String? id,
    String? userId,
    String? accountId,
    String? categoryId,
    String? contactId,
    TransactionType? type,
    Decimal? amount,
    DateTime? transactionDate,
    String? note,
    String? description,
    String? paymentMethod,
    String? transferId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      contactId: contactId ?? this.contactId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      transactionDate: transactionDate ?? this.transactionDate,
      note: note ?? this.note,
      description: description ?? this.description,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      transferId: transferId ?? this.transferId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
