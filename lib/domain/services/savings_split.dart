import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';

/// One goal and the share of an income that goes to it.
typedef SavingsPart = ({String goalId, Decimal amount});

/// Rows to write so a transaction's contributions match what the form asks
/// for. [deletes] holds contribution ids.
class SplitChanges {
  const SplitChanges({
    this.inserts = const [],
    this.updates = const [],
    this.deletes = const [],
  });

  final List<SavingsContribution> inserts;
  final List<SavingsContribution> updates;
  final List<String> deletes;

  bool get isEmpty => inserts.isEmpty && updates.isEmpty && deletes.isEmpty;
}

/// Rules for putting parts of an income into savings goals
/// (docs/superpowers/specs/2026-10-24-income-savings-split-design.md).
abstract final class SavingsSplit {
  /// Returns an English message key for the first broken rule, or null when
  /// [parts] are valid. Callers apply `.tr`.
  static String? validate({
    required TransactionType type,
    required Decimal amount,
    required List<SavingsPart> parts,
  }) {
    if (parts.isEmpty) return null;
    if (type != TransactionType.income) {
      return 'Only an income can go to savings';
    }
    if (parts.any((SavingsPart p) => p.amount <= Decimal.zero)) {
      return 'Amount must be more than zero';
    }
    if (parts.map((SavingsPart p) => p.goalId).toSet().length != parts.length) {
      return 'This goal is already used';
    }
    if (total(parts) > amount) return "Savings can't be more than the income";
    return null;
  }

  /// Sum of the amounts of [parts].
  static Decimal total(Iterable<SavingsPart> parts) =>
      parts.fold(Decimal.zero, (Decimal sum, SavingsPart p) => sum + p.amount);

  /// Compares the [current] live rows of [transactionId] with the [wanted]
  /// parts, matching by goal. New rows get an empty user id, which the
  /// repository fills in on save. When [current] holds several rows for one
  /// goal (a restore or a second device can add one), the first is kept and
  /// the rest are deleted.
  static SplitChanges diff({
    required String transactionId,
    required List<SavingsContribution> current,
    required List<SavingsPart> wanted,
    required String Function() newId,
    required DateTime now,
  }) {
    final Map<String, SavingsContribution> byGoal = {};
    for (final SavingsContribution c in current) {
      byGoal.putIfAbsent(c.goalId, () => c);
    }
    final Set<String> kept = {};
    final List<SavingsContribution> inserts = [];
    final List<SavingsContribution> updates = [];
    for (final SavingsPart part in wanted) {
      final SavingsContribution? existing = byGoal.remove(part.goalId);
      if (existing == null) {
        inserts.add(
          SavingsContribution(
            id: newId(),
            userId: '',
            transactionId: transactionId,
            goalId: part.goalId,
            amount: part.amount,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        kept.add(existing.id);
        if (existing.amount != part.amount) {
          updates.add(existing.copyWith(amount: part.amount, updatedAt: now));
        }
      }
    }
    return SplitChanges(
      inserts: inserts,
      updates: updates,
      deletes: [
        for (final SavingsContribution c in current)
          if (!kept.contains(c.id)) c.id,
      ],
    );
  }

  /// Total contributed per goal id.
  static Map<String, Decimal> sumByGoal(Iterable<SavingsContribution> live) {
    final Map<String, Decimal> sums = {};
    for (final SavingsContribution c in live) {
      sums[c.goalId] = (sums[c.goalId] ?? Decimal.zero) + c.amount;
    }
    return sums;
  }
}
