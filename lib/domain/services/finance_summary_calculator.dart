import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/account_balance_calculator.dart';

class PeriodSummary {
  const PeriodSummary({required this.income, required this.expense});

  static final PeriodSummary zero = PeriodSummary(
    income: Decimal.zero,
    expense: Decimal.zero,
  );

  final Decimal income;
  final Decimal expense;
  Decimal get net => income - expense;
}

class KhataSummary {
  const KhataSummary({required this.receivable, required this.payable});

  static final KhataSummary zero = KhataSummary(
    receivable: Decimal.zero,
    payable: Decimal.zero,
  );

  final Decimal receivable;
  final Decimal payable;
}

/// Dashboard and report totals, kept out of widgets and controllers
/// (docs/05_FINANCIAL_LOGIC.md). Account balances themselves come from
/// [AccountBalanceCalculator].
abstract final class FinanceSummaryCalculator {
  /// Current balance per account id.
  static Map<String, Decimal> accountBalances(
    List<Account> accounts,
    List<Transaction> transactions,
  ) {
    final Map<String, List<Transaction>> byAccount =
        <String, List<Transaction>>{};
    for (final Transaction t in transactions) {
      if (t.deletedAt == null) {
        byAccount.putIfAbsent(t.accountId, () => <Transaction>[]).add(t);
      }
    }
    return <String, Decimal>{
      for (final Account a in accounts)
        a.id: AccountBalanceCalculator.calculateBalance(
          a.openingBalance,
          byAccount[a.id] ?? const <Transaction>[],
        ),
    };
  }

  static Decimal sum(Iterable<Decimal> values) =>
      values.fold(Decimal.zero, (Decimal total, Decimal v) => total + v);

  /// Income and expense (transfers and adjustments excluded) with
  /// `from <= date < to`.
  static PeriodSummary period(
    List<Transaction> transactions,
    DateTime from,
    DateTime to,
  ) {
    Decimal income = Decimal.zero;
    Decimal expense = Decimal.zero;
    for (final Transaction t in transactions) {
      if (t.deletedAt != null) continue;
      if (t.transactionDate.isBefore(from) || !t.transactionDate.isBefore(to)) {
        continue;
      }
      if (t.type == TransactionType.income) income += t.amount;
      if (t.type == TransactionType.expense) expense += t.amount;
    }
    return PeriodSummary(income: income, expense: expense);
  }

  /// Totals owed to the user and by the user, across all contacts.
  static KhataSummary khata(
    List<Contact> contacts,
    List<ContactTransaction> contactTransactions,
  ) {
    final Map<String, List<ContactTransaction>> byContact =
        <String, List<ContactTransaction>>{};
    for (final ContactTransaction t in contactTransactions) {
      byContact.putIfAbsent(t.contactId, () => <ContactTransaction>[]).add(t);
    }
    Decimal receivable = Decimal.zero;
    Decimal payable = Decimal.zero;
    for (final Contact c in contacts) {
      final List<ContactTransaction> list =
          byContact[c.id] ?? const <ContactTransaction>[];
      receivable += c.getReceivable(list);
      payable += c.getPayable(list);
    }
    return KhataSummary(receivable: receivable, payable: payable);
  }
}
