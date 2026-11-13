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

  /// The photo's object name in the avatars bucket (PhotoStore), or null.
  final String? avatarPath;

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
    this.avatarPath,
  });

  /// Opening balance with its direction: positive when they owe us
  /// (receivable), negative when we owe them (payable).
  Decimal get signedOpeningBalance =>
      openingBalanceType == 'payable' ? -openingBalance : openingBalance;

  /// The balance once [entriesTotal], the entries' signed amounts summed
  /// (ContactTransaction.signedAmount), is added to the opening balance.
  /// Positive = receivable (they owe us), negative = payable (we owe them).
  Decimal balanceWith(Decimal entriesTotal) =>
      signedOpeningBalance + entriesTotal;

  /// The balance from the opening balance and [transactions] (deleted ones
  /// are skipped).
  Decimal getCurrentBalance(List<ContactTransaction> transactions) {
    Decimal total = Decimal.zero;
    for (final transaction in transactions) {
      if (transaction.deletedAt == null) total += transaction.signedAmount;
    }
    return balanceWith(total);
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

  /// Set when the row is derived from a split expense or settlement.
  final String? splitExpenseId;

  /// Set when the row is derived from a split settlement.
  final String? splitSettlementId;

  /// A derived entry is owned by its split group: it can only be changed
  /// there, not directly (docs/05, "Guards").
  bool get isSplitDerived =>
      splitExpenseId != null || splitSettlementId != null;

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
    this.splitExpenseId,
    this.splitSettlementId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// How this entry moves the contact's balance: positive when they owe us
  /// more (credit, or we paid back), negative when we owe them more (debit,
  /// or they paid back). Adjustments apply as entered.
  Decimal get signedAmount => signedOf(type, amount);

  /// [signedAmount] for an entry of [type] and [amount], for totals read
  /// without loading whole entries.
  static Decimal signedOf(ContactTransactionType type, Decimal amount) =>
      switch (type) {
        ContactTransactionType.credit ||
        ContactTransactionType.paymentMade ||
        ContactTransactionType.adjustment => amount,
        ContactTransactionType.debit ||
        ContactTransactionType.paymentReceived => -amount,
      };
}
