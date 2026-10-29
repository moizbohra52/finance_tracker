import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_calculator.dart';
import 'package:rational/rational.dart';

/// What [debtorMemberId] owes [creditorMemberId]; [amount] > 0.
class PairBalance {
  const PairBalance({
    required this.debtorMemberId,
    required this.creditorMemberId,
    required this.amount,
  });

  final String debtorMemberId;
  final String creditorMemberId;
  final Decimal amount;
}

/// Who owes whom inside one group, from its live expenses and settlements.
class GroupBalances {
  const GroupBalances({required this.memberNets, required this.pairs});

  /// Per member `Σ(paid − share) + settlements paid − settlements received`;
  /// the values add to zero.
  final Map<String, Decimal> memberNets;

  /// Pairwise debts, amount descending then debtor id; pairs with 0 omitted.
  final List<PairBalance> pairs;

  Decimal netOf(String memberId) => memberNets[memberId] ?? Decimal.zero;
}

/// Group balance rules (docs/05_FINANCIAL_LOGIC.md). Inputs are live rows
/// only.
abstract final class SplitBalances {
  /// The user↔friend pairs sum the per-expense khata nets (so they equal the
  /// khata exactly); friend↔friend pairs sum the expenses exactly and round
  /// to paise once.
  static GroupBalances compute({
    required String meId,
    required List<SplitExpense> expenses,
    required Map<String, List<SplitPart>> partsByExpense,
    required List<SplitSettlement> settlements,
  }) {
    final Map<String, Decimal> memberNets = <String, Decimal>{};
    // Signed debt over an unordered pair: positive means the pair's first id
    // owes the second. User pairs are paise sums of the khata nets; friend
    // pairs are exact rationals rounded once at the end.
    final Map<String, Decimal> userPairDebt = <String, Decimal>{};
    final Map<String, Rational> friendPairDebt = <String, Rational>{};

    void addMemberNet(String memberId, Decimal delta) {
      memberNets[memberId] = (memberNets[memberId] ?? Decimal.zero) + delta;
    }

    /// Grows [from]'s debt to [to] by [signedAmount] (negative shrinks it).
    void applyDebt(String from, String to, Decimal signedAmount) {
      final String pairKey = _pairKey(from, to);
      final (String a, String b) = _pairIds(pairKey);
      if (from == meId || to == meId) {
        final Decimal signed = userPairDebt[pairKey] ?? Decimal.zero;
        final Decimal updated =
            signed + (from == a ? signedAmount : -signedAmount);
        if (updated == Decimal.zero) {
          userPairDebt.remove(pairKey);
        } else {
          userPairDebt[pairKey] = updated;
        }
      } else {
        final Rational signed = friendPairDebt[pairKey] ?? Rational.zero;
        final Rational delta = from == a
            ? signedAmount.toRational()
            : -signedAmount.toRational();
        final Rational updated = signed + delta;
        if (updated == Rational.zero) {
          friendPairDebt.remove(pairKey);
        } else {
          friendPairDebt[pairKey] = updated;
        }
      }
    }

    for (final SplitExpense expense in expenses) {
      if (!expense.isLive) continue;
      final List<SplitPart> parts =
          (partsByExpense[expense.id] ?? const <SplitPart>[])
              .where((SplitPart p) => p.isLive)
              .toList();
      if (parts.isEmpty) continue;
      final Map<String, Decimal> paid = <String, Decimal>{
        for (final SplitPart p in parts) p.memberId: p.paidAmount,
      };
      final Map<String, Decimal> shares = <String, Decimal>{
        for (final SplitPart p in parts) p.memberId: p.shareAmount,
      };
      final List<String> memberIds =
          parts.map((SplitPart p) => p.memberId).toList()..sort();
      // The friend's debt to the user for this expense, as the khata sees it.
      final Map<String, Decimal> nets = SplitCalculator.friendNets(
        total: expense.totalAmount,
        meId: meId,
        paid: paid,
        shares: shares,
      );
      for (final String f in memberIds) {
        if (f == meId) continue;
        final Decimal nf = nets[f] ?? Decimal.zero;
        if (nf != Decimal.zero) applyDebt(f, meId, nf);
        addMemberNet(
          f,
          (paid[f] ?? Decimal.zero) - (shares[f] ?? Decimal.zero),
        );
      }
      addMemberNet(
        meId,
        (paid[meId] ?? Decimal.zero) - (shares[meId] ?? Decimal.zero),
      );
      for (int i = 0; i < memberIds.length; i++) {
        for (int j = i + 1; j < memberIds.length; j++) {
          final String a = memberIds[i];
          final String b = memberIds[j];
          if (a == meId || b == meId) continue;
          // debt(a → b) = (share_a × paid_b − share_b × paid_a) / T, exact.
          final Rational debtAToB =
              (shares[a]! * paid[b]! - shares[b]! * paid[a]!).toRational() /
              expense.totalAmount.toRational();
          final String pairKey = _pairKey(a, b);
          friendPairDebt[pairKey] =
              (friendPairDebt[pairKey] ?? Rational.zero) + debtAToB;
        }
      }
    }
    for (final SplitSettlement s in settlements) {
      if (!s.isLive) continue;
      addMemberNet(s.fromMemberId, s.amount);
      addMemberNet(s.toMemberId, -s.amount);
      // A settlement from → to reduces what from owes to.
      applyDebt(s.fromMemberId, s.toMemberId, -s.amount);
    }
    final List<PairBalance> pairs = <PairBalance>[];
    userPairDebt.forEach((String pairKey, Decimal signed) {
      final (String a, String b) = _pairIds(pairKey);
      _pushPair(pairs, a, b, signed);
    });
    friendPairDebt.forEach((String pairKey, Rational signed) {
      final (String a, String b) = _pairIds(pairKey);
      _pushPair(
        pairs,
        a,
        b,
        SplitCalculator.fromPaise(_roundPaise(signed * Rational.fromInt(100))),
      );
    });
    pairs.sort((PairBalance a, PairBalance b) {
      final int byAmount = b.amount.compareTo(a.amount);
      return byAmount != 0
          ? byAmount
          : a.debtorMemberId.compareTo(b.debtorMemberId);
    });
    return GroupBalances(memberNets: memberNets, pairs: pairs);
  }

  /// Rounds a rational to whole paise (halves away from zero).
  static BigInt _roundPaise(Rational value) {
    final BigInt d = value.denominator;
    BigInt q = value.numerator ~/ d;
    BigInt r = value.numerator - q * d;
    if (r < BigInt.zero) {
      q -= BigInt.one;
      r += d;
    }
    if (r * BigInt.two >= d) q += BigInt.one;
    return q;
  }

  static void _pushPair(
    List<PairBalance> pairs,
    String a,
    String b,
    Decimal signed,
  ) {
    if (signed == Decimal.zero) return;
    if (signed > Decimal.zero) {
      pairs.add(
        PairBalance(debtorMemberId: a, creditorMemberId: b, amount: signed),
      );
    } else {
      pairs.add(
        PairBalance(debtorMemberId: b, creditorMemberId: a, amount: -signed),
      );
    }
  }

  /// Canonical key for an unordered pair, smaller id first.
  static String _pairKey(String a, String b) =>
      a.compareTo(b) < 0 ? '$a\u0000$b' : '$b\u0000$a';

  static (String, String) _pairIds(String pairKey) {
    final int sep = pairKey.indexOf('\u0000');
    return (pairKey.substring(0, sep), pairKey.substring(sep + 1));
  }
}
