import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/loan.dart';

/// Shared parsing for the loan row mappings.
abstract final class _LoanJson {
  /// Rows written locally and payloads sent to the server carry no timestamps
  /// (the clock/trigger sets them), so parsing accepts them missing.
  static DateTime when(dynamic v) => v == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.parse(v as String);

  /// A timestamp as local time: the calculator reads the DateTime's own
  /// year, month and day.
  static DateTime? local(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  static Decimal? decimal(dynamic v) =>
      v == null ? null : Decimal.parse(v.toString());

  /// A `YYYY-MM-DD` date (a server `date` column, possibly with a time part)
  /// as a local calendar date.
  static DateTime? date(dynamic v) {
    if (v == null) return null;
    final String text = v as String;
    return DateTime(
      int.parse(text.substring(0, 4)),
      int.parse(text.substring(5, 7)),
      int.parse(text.substring(8, 10)),
    );
  }

  static String dateText(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Row mapping for public.loans.
abstract final class LoanModel {
  static Loan fromJson(Map<String, dynamic> json) => Loan(
    id: json['id'] as String,
    userId: (json['user_id'] ?? '') as String,
    direction: LoanDirection.values.byName(json['direction'] as String),
    method: LoanMethod.fromValue(json['method'] as String),
    name: json['name'] as String,
    contactId: json['contact_id'] as String?,
    accountId: json['account_id'] as String,
    principal: Decimal.parse(json['principal'].toString()),
    annualRate: Decimal.parse(json['annual_rate'].toString()),
    tenureMonths: (json['tenure_months'] as num?)?.toInt(),
    emiAmount: _LoanJson.decimal(json['emi_amount']),
    startDate: _LoanJson.date(json['start_date'])!,
    firstDueDate: _LoanJson.date(json['first_due_date']),
    movedMoney: json['moved_money'] == true || json['moved_money'] == 1,
    closedAt: _LoanJson.local(json['closed_at']),
    note: json['note'] as String?,
    createdAt: _LoanJson.when(json['created_at']),
    updatedAt: _LoanJson.when(json['updated_at']),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
  );

  static Map<String, dynamic> toJson(Loan l) => <String, dynamic>{
    'id': l.id,
    'user_id': l.userId,
    'direction': l.direction.name,
    'method': l.method.value,
    'name': l.name,
    'contact_id': l.contactId,
    'account_id': l.accountId,
    'principal': l.principal.toString(),
    'annual_rate': l.annualRate.toString(),
    'tenure_months': l.tenureMonths,
    'emi_amount': l.emiAmount?.toString(),
    'start_date': _LoanJson.dateText(l.startDate),
    'first_due_date': l.firstDueDate == null
        ? null
        : _LoanJson.dateText(l.firstDueDate!),
    'moved_money': l.movedMoney,
    'closed_at': l.closedAt?.toUtc().toIso8601String(),
    'note': l.note,
  };
}

/// Row mapping for public.loan_payments.
abstract final class LoanPaymentModel {
  static LoanPayment fromJson(Map<String, dynamic> json) => LoanPayment(
    id: json['id'] as String,
    userId: (json['user_id'] ?? '') as String,
    loanId: json['loan_id'] as String,
    accountId: json['account_id'] as String,
    kind: LoanPaymentKind.values.byName(json['kind'] as String),
    paidAt: _LoanJson.local(json['paid_at'])!,
    amount: Decimal.parse(json['amount'].toString()),
    principalPart: Decimal.parse(json['principal_part'].toString()),
    interestPart: Decimal.parse(json['interest_part'].toString()),
    note: json['note'] as String?,
    createdAt: _LoanJson.when(json['created_at']),
    updatedAt: _LoanJson.when(json['updated_at']),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
  );

  static Map<String, dynamic> toJson(LoanPayment p) => <String, dynamic>{
    'id': p.id,
    'user_id': p.userId,
    'loan_id': p.loanId,
    'account_id': p.accountId,
    'kind': p.kind.name,
    'paid_at': p.paidAt.toUtc().toIso8601String(),
    'amount': p.amount.toString(),
    'principal_part': p.principalPart.toString(),
    'interest_part': p.interestPart.toString(),
    'note': p.note,
  };
}
