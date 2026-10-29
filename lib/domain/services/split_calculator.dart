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
}
