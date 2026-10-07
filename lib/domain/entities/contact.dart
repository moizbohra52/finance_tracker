import 'package:decimal/decimal.dart';

class Contact {
  final String id;
  final String userId;
  final String name;
  final String? mobile;
  final String? email;
  final String? address;
  final String? notes;
  final Decimal openingBalance;
  final String openingBalanceType; // 'receivable' or 'payable'
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Contact({
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

  // Get current balance based on opening balance and transactions
  // This would typically be calculated by a service/repository
  Decimal getCurrentBalance(List<ContactTransaction> transactions) {
    Decimal balance = openingBalance;

    // Apply opening balance type
    if (openingBalanceType == 'payable') {
      balance =
          Decimal.zero -
          balance; // Payable opening balance is negative (we owe)
    }
    // Receivable opening balance is positive (they owe us)

    // Apply transactions
    for (final transaction in transactions) {
      if (transaction.deletedAt == null) {
        switch (transaction.type) {
          case ContactTransactionType.credit:
            // Credit increases what they owe us (receivable increases)
            balance += transaction.amount;
            break;
          case ContactTransactionType.debit:
            // Debit increases what we owe them (payable increases, receivable decreases)
            balance -= transaction.amount;
            break;
          case ContactTransactionType.paymentReceived:
            // Payment received decreases what they owe us
            balance -= transaction.amount;
            break;
          case ContactTransactionType.paymentMade:
            // Payment made decreases what we owe them
            balance += transaction.amount;
            break;
          case ContactTransactionType.adjustment:
            // Adjustment can be positive or negative based on context
            // For simplicity, we'll treat it as directly affecting the balance
            balance += transaction.amount;
            break;
        }
      }
    }

    // Return absolute value for display, with sign indicating direction
    // Positive = receivable (they owe us), Negative = payable (we owe them)
    return balance;
  }

  // Get receivable amount (positive if they owe us, 0 if we owe them or settled)
  Decimal getReceivable(List<ContactTransaction> transactions) {
    final balance = getCurrentBalance(transactions);
    return balance > Decimal.zero ? balance : Decimal.zero;
  }

  // Get payable amount (positive if we owe them, 0 if they owe us or settled)
  Decimal getPayable(List<ContactTransaction> transactions) {
    final balance = getCurrentBalance(transactions);
    return balance < Decimal.zero ? Decimal.zero - balance : Decimal.zero;
  }

  // Check if contact has a balance (either receivable or payable)
  bool hasBalance(List<ContactTransaction> transactions) {
    return getCurrentBalance(transactions) != Decimal.zero;
  }
}

enum ContactTransactionType {
  credit,
  debit,
  paymentReceived,
  paymentMade,
  adjustment,
}

class ContactTransaction {
  final String id;
  final String userId;
  final String contactId;
  final ContactTransactionType type;
  final Decimal amount;
  final DateTime transactionDate;
  final DateTime? dueDate;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  ContactTransaction({
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
}
