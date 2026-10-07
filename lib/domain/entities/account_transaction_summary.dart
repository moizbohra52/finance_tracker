import 'package:decimal/decimal.dart';

/// Summary of transactions for an account, used by the detail view.
class AccountTransactionSummary {
  final Decimal balance;
  final Decimal totalIncome;
  final Decimal totalExpense;
  final int transactionCount;

  AccountTransactionSummary({
    required this.balance,
    required this.totalIncome,
    required this.totalExpense,
    required this.transactionCount,
  });
}
