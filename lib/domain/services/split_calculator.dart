import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/split.dart';

/// Money rules for split expenses (docs/05_FINANCIAL_LOGIC.md). All maths is
/// exact: amounts are `Decimal`, arithmetic happens on paise (`BigInt`).
abstract final class SplitCalculator {
  static final Decimal _hundred = Decimal.fromInt(100);

  /// [amount] in paise. Only safe for amounts with at most 2 decimals.
  static BigInt paise(Decimal amount) => (amount * _hundred).toBigInt();

  /// A paise amount back to a `Decimal`.
  static Decimal fromPaise(BigInt paise) =>
      Decimal.fromBigInt(paise) * Decimal.parse('0.01');

  /// True when [amount] needs more than 2 decimals: `amount * 100` is not an
  /// integer.
  static bool hasSubPaise(Decimal amount) => !(amount * _hundred).isInteger;

  static BigInt _gcd(BigInt a, BigInt b) =>
      b == BigInt.zero ? a : _gcd(b, a % b);

  static BigInt _lcm(BigInt a, BigInt b) => a * b ~/ _gcd(a, b);

  /// Splits the paise of [total] by [weights] with the largest remainder
  /// method; keys are member ids, ties go by ascending member id, a weight of
  /// 0 gets 0. The parts always add up to [total] exactly.
  static Map<String, Decimal> allocate(
    Decimal total,
    Map<String, Decimal> weights,
  ) {
    final BigInt totalPaise = paise(total);
    // Weights are exact rationals; scale them to integers over one common
    // denominator so the remainders compare exactly.
    BigInt denom = BigInt.one;
    for (final Decimal w in weights.values) {
      denom = _lcm(denom, w.toRational().denominator);
    }
    final Map<String, BigInt> scaled = <String, BigInt>{};
    BigInt weightSum = BigInt.zero;
    weights.forEach((String id, Decimal w) {
      final BigInt wi =
          w.toRational().numerator * (denom ~/ w.toRational().denominator);
      scaled[id] = wi;
      weightSum += wi;
    });
    final Map<String, Decimal> result = <String, Decimal>{
      for (final String id in weights.keys) id: Decimal.zero,
    };
    if (weightSum == BigInt.zero) return result;
    final Map<String, BigInt> remainders = <String, BigInt>{};
    BigInt allocated = BigInt.zero;
    scaled.forEach((String id, BigInt wi) {
      final BigInt exact = totalPaise * wi;
      final BigInt base = exact ~/ weightSum;
      remainders[id] = exact % weightSum;
      result[id] = fromPaise(base);
      allocated += base;
    });
    BigInt leftover = totalPaise - allocated;
    final List<String> order = scaled.keys.toList()
      ..sort((String a, String b) {
        final int byRemainder = remainders[b]!.compareTo(remainders[a]!);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (int i = 0; i < order.length && leftover > BigInt.zero; i++) {
      result[order[i]] = fromPaise(paise(result[order[i]]!) + BigInt.one);
      leftover -= BigInt.one;
    }
    return result;
  }

  /// Returns the first English message key a mode's inputs break, or null
  /// when they are valid. Callers apply `.tr`.
  static String? validateInputs(
    SplitMode mode,
    Decimal total,
    Map<String, Decimal> inputs,
  ) {
    final Decimal sum = inputs.values.fold(
      Decimal.zero,
      (Decimal a, Decimal b) => a + b,
    );
    switch (mode) {
      case SplitMode.equal:
        if (!inputs.values.any((Decimal v) => v > Decimal.zero)) {
          return 'Tick at least one person';
        }
        return null;
      case SplitMode.exact:
        return sum == total ? null : 'The shares must add up to the total';
      case SplitMode.percent:
        return sum == _hundred ? null : 'Percentages must add up to 100';
      case SplitMode.shares:
        final bool wholeAndNotNegative = inputs.values.every(
          (Decimal v) => v.isInteger && v >= Decimal.zero,
        );
        final bool anyPositive = inputs.values.any(
          (Decimal v) => v > Decimal.zero,
        );
        return wholeAndNotNegative && anyPositive
            ? null
            : 'Enter at least one share';
    }
  }

  /// The share amount of every member for [mode] from the typed [inputs].
  /// Equal gives a weight of 1 to every input > 0; exact takes the amounts
  /// as typed; percent and shares allocate by the inputs as weights.
  static Map<String, Decimal> sharesFor(
    SplitMode mode,
    Decimal total,
    Map<String, Decimal> inputs,
  ) {
    switch (mode) {
      case SplitMode.equal:
        return allocate(total, <String, Decimal>{
          for (final MapEntry<String, Decimal> e in inputs.entries)
            e.key: e.value > Decimal.zero ? Decimal.one : Decimal.zero,
        });
      case SplitMode.exact:
        return Map<String, Decimal>.of(inputs);
      case SplitMode.percent:
      case SplitMode.shares:
        return allocate(total, inputs);
    }
  }

  /// Returns the first English message key an expense breaks, in this order,
  /// or null when it is valid. Blank or absent members count as 0.
  static String? validate({
    required Decimal total,
    required Map<String, Decimal> paid,
    required Map<String, Decimal> shares,
    required String meId,
    required String? categoryId,
    required String? accountId,
  }) {
    final List<Decimal> all = <Decimal>[
      total,
      ...paid.values,
      ...shares.values,
    ];
    if (total <= Decimal.zero || all.any((Decimal v) => v < Decimal.zero)) {
      return 'Amount must be more than zero';
    }
    if (all.any(hasSubPaise)) return 'Amounts can have at most 2 decimals';
    if (_sum(paid.values) != total) {
      return 'What was paid must add up to the total';
    }
    if (_sum(shares.values) != total) {
      return 'The shares must add up to the total';
    }
    final Decimal paidMe = paid[meId] ?? Decimal.zero;
    final Decimal shareMe = shares[meId] ?? Decimal.zero;
    final Set<String> memberIds = <String>{...paid.keys, ...shares.keys};
    final bool hasFriend = memberIds
        .where((String id) => id != meId)
        .any(
          (String id) =>
              (paid[id] ?? Decimal.zero) > Decimal.zero ||
              (shares[id] ?? Decimal.zero) > Decimal.zero,
        );
    if (!hasFriend) return 'Add at least one friend to this expense';
    if (shareMe > Decimal.zero && categoryId == null) {
      return 'Choose a category';
    }
    if ((paidMe > Decimal.zero || shareMe > Decimal.zero) &&
        accountId == null) {
      return 'Choose an account';
    }
    return null;
  }

  static Decimal _sum(Iterable<Decimal> values) =>
      values.fold(Decimal.zero, (Decimal a, Decimal b) => a + b);

  /// The user's net with each friend on one expense
  /// (docs/05_FINANCIAL_LOGIC.md): `n_f = (share_f × paid_me − share_me ×
  /// paid_f) / T`, each rounded to paise with the largest remainder method so
  /// the values sum to exactly `paid_me − share_me`. A positive value means
  /// the friend owes the user. Keys are every member id except [meId].
  static Map<String, Decimal> friendNets({
    required Decimal total,
    required String meId,
    required Map<String, Decimal> paid,
    required Map<String, Decimal> shares,
  }) {
    final Decimal paidMe = paid[meId] ?? Decimal.zero;
    final Decimal shareMe = shares[meId] ?? Decimal.zero;
    final Set<String> friendIds = <String>{
      ...paid.keys.where((String id) => id != meId),
      ...shares.keys.where((String id) => id != meId),
    };
    if (friendIds.isEmpty) return const <String, Decimal>{};
    // Exact net per friend as a rational over paise, all over one common
    // denominator so the remainders compare exactly.
    BigInt denom = BigInt.one;
    final Map<String, BigInt> numerators = <String, BigInt>{};
    final Map<String, BigInt> denominators = <String, BigInt>{};
    for (final String id in friendIds) {
      final Decimal net =
          (shares[id] ?? Decimal.zero) * paidMe -
          shareMe * (paid[id] ?? Decimal.zero);
      final r = net * _hundred / total;
      numerators[id] = r.numerator;
      denominators[id] = r.denominator;
      denom = denom * r.denominator;
    }
    // Floor each exact value; the leftover paise goes to the largest
    // remainders, ties by ascending member id.
    BigInt flooredSum = BigInt.zero;
    final Map<String, BigInt> bases = <String, BigInt>{};
    final Map<String, BigInt> remainders = <String, BigInt>{};
    numerators.forEach((String id, BigInt n) {
      final BigInt common = n * (denom ~/ denominators[id]!);
      BigInt q = common ~/ denom;
      BigInt r = common - q * denom;
      if (r < BigInt.zero) {
        // `~/` truncates towards zero; floor so the remainder is in [0, denom).
        q -= BigInt.one;
        r += denom;
      }
      bases[id] = q;
      remainders[id] = r;
      flooredSum += q;
    });
    final Decimal paidMinusShare = paidMe - shareMe;
    final BigInt target = paise(paidMinusShare);
    BigInt leftover = target - flooredSum;
    final List<String> order = numerators.keys.toList()
      ..sort((String a, String b) {
        final int byRemainder = remainders[b]!.compareTo(remainders[a]!);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    final Map<String, Decimal> nets = <String, Decimal>{
      for (final String id in friendIds) id: fromPaise(bases[id]!),
    };
    for (int i = 0; i < order.length && leftover > BigInt.zero; i++) {
      nets[order[i]] = fromPaise(paise(nets[order[i]]!) + BigInt.one);
      leftover -= BigInt.one;
    }
    return nets;
  }

  /// The rows the user's own books get from one expense: their share, the
  /// balance movement on their account and their net with each friend.
  static SplitUserRows userRows({
    required Decimal total,
    required String meId,
    required Map<String, Decimal> paid,
    required Map<String, Decimal> shares,
  }) {
    final Decimal paidMe = paid[meId] ?? Decimal.zero;
    final Decimal shareMe = shares[meId] ?? Decimal.zero;
    return SplitUserRows(
      expenseShare: shareMe,
      balanceAmount: (paidMe - shareMe).abs(),
      balanceIsPaidForOthers: paidMe > shareMe,
      contactNets: friendNets(
        total: total,
        meId: meId,
        paid: paid,
        shares: shares,
      ),
    );
  }
}

/// The user's own derived rows for one expense (docs/05_FINANCIAL_LOGIC.md).
class SplitUserRows {
  const SplitUserRows({
    required this.expenseShare,
    required this.balanceAmount,
    required this.balanceIsPaidForOthers,
    required this.contactNets,
  });

  /// The user's own share of the expense.
  final Decimal expenseShare;

  /// `|paid_me − share_me|`; the account moves by this much.
  final Decimal balanceAmount;

  /// True when the user paid more than their share (`payment_made`), false
  /// when others covered part of the user's share (`payment_received`).
  final bool balanceIsPaidForOthers;

  /// The user's net with each friend; positive means the friend owes them.
  final Map<String, Decimal> contactNets;
}
