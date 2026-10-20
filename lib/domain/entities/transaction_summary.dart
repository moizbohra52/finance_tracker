import 'package:decimal/decimal.dart';

/// Aggregated total inflow, outflow, net amount, and transaction count
/// for all transactions matching a query/filter, regardless of pagination.
class TransactionSummary {
  const TransactionSummary({
    required this.totalInflow,
    required this.totalOutflow,
    this.totalCount = 0,
  });

  final Decimal totalInflow;
  final Decimal totalOutflow;
  final int totalCount;

  Decimal get netAmount => totalInflow - totalOutflow;

  static final TransactionSummary zero = TransactionSummary(
    totalInflow: Decimal.zero,
    totalOutflow: Decimal.zero,
    totalCount: 0,
  );
}
