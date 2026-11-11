import 'package:uuid/uuid.dart';

/// Deterministic uuid v5 ids for a loan's rows and their derived rows, so
/// every device and every retry writes the same row (pattern of
/// `split_ids.dart`).
abstract final class LoanIds {
  /// The disbursement / lending transaction of a loan that moved money.
  static String loanRow(String loanId) => _v5('loan:$loanId');

  /// The transaction for the principal part of one payment.
  static String paymentPrincipal(String paymentId) =>
      _v5('loan-payment:$paymentId:principal');

  /// The transaction for the interest part of one payment.
  static String paymentInterest(String paymentId) =>
      _v5('loan-payment:$paymentId:interest');

  /// The reminder of a loan's next due date.
  static String reminder(String loanId) => _v5('loan-reminder:$loanId');

  static String _v5(String name) => const Uuid().v5(Namespace.url.value, name);
}
