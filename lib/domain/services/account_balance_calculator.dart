import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';

class AccountBalanceCalculator {
  AccountBalanceCalculator._();

  /// Account balance per docs/05_FINANCIAL_LOGIC.md:
  ///   balance = opening_balance + income + transfer_in + adjustments_in - expense - transfer_out - adjustments_out
  /// Transaction types that do NOT affect an account balance (credit/debit khata,
  /// payment_received/payment_made when no account is involved) are handled by
  /// the caller deciding which transactions to include.
  static Decimal calculateBalance(
    Decimal openingBalance,
    List<Transaction> transactions,
  ) {
    if (transactions.isEmpty) {
      return openingBalance;
    }
    Decimal balance = openingBalance;
    for (final transaction in transactions) {
      switch (transaction.type) {
        case TransactionType.income:
        case TransactionType.transferIn:
        case TransactionType.adjustmentIn:
        case TransactionType.paymentReceived:
          balance += transaction.amount;
          break;
        case TransactionType.expense:
        case TransactionType.transferOut:
        case TransactionType.adjustmentOut:
        case TransactionType.paymentMade:
          balance -= transaction.amount;
          break;
        case TransactionType.openingBalance:
          // Opening balance transactions are already accounted for in the
          // openingBalance parameter.
          break;
      }
    }
    return balance;
  }

  /// Net income for an account: sum of income transactions.
  static Decimal sumIncome(List<Transaction> transactions) {
    Decimal total = Decimal.zero;
    for (final t in transactions) {
      if (t.type == TransactionType.income ||
          t.type == TransactionType.transferIn) {
        total += t.amount;
      }
    }
    return total;
  }

  /// Net expense for an account: sum of expense transactions (positive number).
  static Decimal sumExpense(List<Transaction> transactions) {
    Decimal total = Decimal.zero;
    for (final t in transactions) {
      if (t.type == TransactionType.expense ||
          t.type == TransactionType.transferOut) {
        total += t.amount;
      }
    }
    return total;
  }
}
