import 'package:decimal/decimal.dart';

/// Whether the user borrowed the money or lent it (stored as its `name`).
enum LoanDirection { taken, given }

/// How a loan is repaid: fixed EMIs, or interest every month with the
/// principal returned whenever the user likes (stored as [value]).
enum LoanMethod {
  emi('emi'),
  monthlyInterest('monthly_interest');

  const LoanMethod(this.value);

  final String value;

  static LoanMethod fromValue(String value) =>
      values.firstWhere((LoanMethod m) => m.value == value);
}

/// A scheduled payment follows the EMI plan; an extra one is a prepayment
/// that is all principal (stored as its `name`).
enum LoanPaymentKind { scheduled, extra }

/// Money borrowed from or lent to someone. [annualRate] is a percent per
/// year; a monthly rate is stored times 12. [startDate] and [firstDueDate]
/// are local calendar dates without a time.
class Loan {
  const Loan({
    required this.id,
    required this.userId,
    required this.direction,
    required this.method,
    required this.name,
    required this.accountId,
    required this.principal,
    required this.annualRate,
    required this.startDate,
    required this.movedMoney,
    required this.createdAt,
    required this.updatedAt,
    this.contactId,
    this.tenureMonths,
    this.emiAmount,
    this.firstDueDate,
    this.closedAt,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final LoanDirection direction;
  final LoanMethod method;
  final String name;
  final String? contactId;
  final String accountId;
  final Decimal principal;
  final Decimal annualRate;

  /// EMI loans only.
  final int? tenureMonths;

  /// EMI loans only; the figure the bank gave, or the calculated EMI.
  final Decimal? emiAmount;
  final DateTime startDate;

  /// EMI loans only.
  final DateTime? firstDueDate;

  /// True when taking or giving the loan moved money on [accountId].
  final bool movedMoney;
  final DateTime? closedAt;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isClosed => closedAt != null;

  bool get isLive => deletedAt == null;

  Loan copyWith({
    String? name,
    String? contactId,
    String? accountId,
    Decimal? principal,
    Decimal? annualRate,
    int? tenureMonths,
    Decimal? emiAmount,
    DateTime? startDate,
    DateTime? firstDueDate,
    bool? movedMoney,
    DateTime? closedAt,
    String? note,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Loan(
      id: id,
      userId: userId,
      direction: direction,
      method: method,
      name: name ?? this.name,
      contactId: contactId ?? this.contactId,
      accountId: accountId ?? this.accountId,
      principal: principal ?? this.principal,
      annualRate: annualRate ?? this.annualRate,
      tenureMonths: tenureMonths ?? this.tenureMonths,
      emiAmount: emiAmount ?? this.emiAmount,
      startDate: startDate ?? this.startDate,
      firstDueDate: firstDueDate ?? this.firstDueDate,
      movedMoney: movedMoney ?? this.movedMoney,
      closedAt: closedAt ?? this.closedAt,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// One payment on a loan, split into the part that repays principal and the
/// part that is interest; [amount] is their sum.
class LoanPayment {
  const LoanPayment({
    required this.id,
    required this.userId,
    required this.loanId,
    required this.accountId,
    required this.kind,
    required this.paidAt,
    required this.amount,
    required this.principalPart,
    required this.interestPart,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String loanId;
  final String accountId;
  final LoanPaymentKind kind;
  final DateTime paidAt;
  final Decimal amount;
  final Decimal principalPart;
  final Decimal interestPart;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;

  LoanPayment copyWith({
    String? accountId,
    LoanPaymentKind? kind,
    DateTime? paidAt,
    Decimal? amount,
    Decimal? principalPart,
    Decimal? interestPart,
    String? note,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return LoanPayment(
      id: id,
      userId: userId,
      loanId: loanId,
      accountId: accountId ?? this.accountId,
      kind: kind ?? this.kind,
      paidAt: paidAt ?? this.paidAt,
      amount: amount ?? this.amount,
      principalPart: principalPart ?? this.principalPart,
      interestPart: interestPart ?? this.interestPart,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
