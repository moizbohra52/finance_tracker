import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_calculator.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Decimal d(String v) => Decimal.parse(v);

  group('allocate', () {
    test('three equal weights give the first member the extra paisa', () {
      expect(
        SplitCalculator.allocate(d('100'), {
          'a': d('1'),
          'b': d('1'),
          'c': d('1'),
        }),
        {'a': d('33.34'), 'b': d('33.33'), 'c': d('33.33')},
      );
    });

    test('weights 1:2 split 100 as 33.33 and 66.67', () {
      expect(SplitCalculator.allocate(d('100'), {'a': d('1'), 'b': d('2')}), {
        'a': d('33.33'),
        'b': d('66.67'),
      });
    });

    test('five paise between two goes 0.03 and 0.02', () {
      expect(
        SplitCalculator.allocate(d('0.05'), {'a': d('50'), 'b': d('50')}),
        {'a': d('0.03'), 'b': d('0.02')},
      );
    });

    test('a zero weight gets zero', () {
      expect(SplitCalculator.allocate(d('10'), {'a': d('0'), 'b': d('1')}), {
        'a': d('0'),
        'b': d('10'),
      });
    });

    test('every allocation sums to its total exactly', () {
      final Random random = Random(7);
      const List<String> ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      for (int i = 0; i < 200; i++) {
        final int memberCount = 1 + random.nextInt(6);
        final Map<String, Decimal> weights = <String, Decimal>{
          for (final String id in ids.take(memberCount))
            id: Decimal.parse('${random.nextInt(1001)}'),
        };
        weights[ids.first] = Decimal.parse('${1 + random.nextInt(1000)}');
        final Decimal total = SplitCalculator.fromPaise(
          BigInt.from(1 + random.nextInt(999999)),
        );
        final Map<String, Decimal> shares = SplitCalculator.allocate(
          total,
          weights,
        );
        final Decimal sum = shares.values.fold(
          Decimal.zero,
          (Decimal a, Decimal b) => a + b,
        );
        expect(sum, total, reason: 'weights $weights total $total');
        expect(shares.values.every((Decimal s) => s >= Decimal.zero), isTrue);
      }
    });
  });

  group('sharesFor', () {
    test('equal skips members with a zero input', () {
      expect(
        SplitCalculator.sharesFor(SplitMode.equal, d('100'), {
          'a': d('1'),
          'b': d('1'),
          'c': d('0'),
        }),
        {'a': d('50'), 'b': d('50'), 'c': d('0')},
      );
    });

    test('percent uses the percentages as weights', () {
      expect(
        SplitCalculator.sharesFor(SplitMode.percent, d('100'), {
          'a': d('50'),
          'b': d('30'),
          'c': d('20'),
        }),
        {'a': d('50'), 'b': d('30'), 'c': d('20')},
      );
    });

    test('exact returns the inputs unchanged', () {
      final Map<String, Decimal> inputs = {'a': d('40'), 'b': d('60')};
      expect(
        SplitCalculator.sharesFor(SplitMode.exact, d('100'), inputs),
        inputs,
      );
    });
  });

  group('validateInputs', () {
    test('equal with nobody ticked is refused', () {
      expect(
        SplitCalculator.validateInputs(SplitMode.equal, d('100'), {
          'a': d('0'),
          'b': d('0'),
        }),
        'Tick at least one person',
      );
    });

    test('exact amounts off by a paisa are refused', () {
      expect(
        SplitCalculator.validateInputs(SplitMode.exact, d('100'), {
          'a': d('50'),
          'b': d('49.99'),
        }),
        'The shares must add up to the total',
      );
    });

    test('percentages adding to 99 are refused', () {
      expect(
        SplitCalculator.validateInputs(SplitMode.percent, d('100'), {
          'a': d('50'),
          'b': d('30'),
          'c': d('19'),
        }),
        'Percentages must add up to 100',
      );
    });

    test('shares with nobody entered are refused', () {
      expect(
        SplitCalculator.validateInputs(SplitMode.shares, d('100'), {
          'a': d('0'),
          'b': d('0'),
        }),
        'Enter at least one share',
      );
    });
  });

  group('validate', () {
    final Map<String, Decimal> dinnerPaid = {'me': d('800'), 'rahul': d('400')};
    final Map<String, Decimal> dinnerShares = {
      'me': d('300'),
      'rahul': d('300'),
      'amit': d('300'),
      'neha': d('300'),
    };

    test('a total of zero or less is refused', () {
      expect(
        SplitCalculator.validate(
          total: d('0'),
          paid: dinnerPaid,
          shares: dinnerShares,
          meId: 'me',
          categoryId: 'c',
          accountId: 'a',
        ),
        'Amount must be more than zero',
      );
    });

    test('a negative amount is refused', () {
      expect(
        SplitCalculator.validate(
          total: d('100'),
          paid: {'me': d('-1'), 'rahul': d('101')},
          shares: dinnerShares,
          meId: 'me',
          categoryId: 'c',
          accountId: 'a',
        ),
        'Amount must be more than zero',
      );
    });

    test('three decimals are refused', () {
      expect(
        SplitCalculator.validate(
          total: d('100.005'),
          paid: {'me': d('100.005')},
          shares: {'me': d('50.005'), 'rahul': d('50')},
          meId: 'me',
          categoryId: 'c',
          accountId: 'a',
        ),
        'Amounts can have at most 2 decimals',
      );
    });

    test('paid that does not add up is refused', () {
      expect(
        SplitCalculator.validate(
          total: d('1200'),
          paid: {'me': d('800'), 'rahul': d('399.99')},
          shares: dinnerShares,
          meId: 'me',
          categoryId: 'c',
          accountId: 'a',
        ),
        'What was paid must add up to the total',
      );
    });

    test('shares that do not add up are refused', () {
      expect(
        SplitCalculator.validate(
          total: d('1200'),
          paid: dinnerPaid,
          shares: {
            'me': d('300'),
            'rahul': d('300'),
            'amit': d('300'),
            'neha': d('299.99'),
          },
          meId: 'me',
          categoryId: 'c',
          accountId: 'a',
        ),
        'The shares must add up to the total',
      );
    });

    test('an expense with only the user is refused', () {
      expect(
        SplitCalculator.validate(
          total: d('100'),
          paid: {'me': d('100')},
          shares: {'me': d('100')},
          meId: 'me',
          categoryId: 'c',
          accountId: 'a',
        ),
        'Add at least one friend to this expense',
      );
    });

    test('a user share without a category is refused', () {
      expect(
        SplitCalculator.validate(
          total: d('1200'),
          paid: dinnerPaid,
          shares: dinnerShares,
          meId: 'me',
          categoryId: null,
          accountId: 'a',
        ),
        'Choose a category',
      );
    });

    test('a user share without an account is refused', () {
      expect(
        SplitCalculator.validate(
          total: d('1200'),
          paid: dinnerPaid,
          shares: dinnerShares,
          meId: 'me',
          categoryId: 'c',
          accountId: null,
        ),
        'Choose an account',
      );
    });

    test('a user who only paid for others needs no category', () {
      expect(
        SplitCalculator.validate(
          total: d('500'),
          paid: {'me': d('500')},
          shares: {'me': d('0'), 'rahul': d('250'), 'amit': d('250')},
          meId: 'me',
          categoryId: null,
          accountId: 'a',
        ),
        isNull,
      );
    });

    test('missing keys count as zero', () {
      expect(
        SplitCalculator.validate(
          total: d('100'),
          paid: {'me': d('100')},
          shares: {'me': d('50'), 'rahul': d('50')},
          meId: 'me',
          categoryId: 'c',
          accountId: 'a',
        ),
        isNull,
      );
    });

    test('the dinner of the spec is valid', () {
      expect(
        SplitCalculator.validate(
          total: d('1200'),
          paid: dinnerPaid,
          shares: dinnerShares,
          meId: 'me',
          categoryId: 'c',
          accountId: 'a',
        ),
        isNull,
      );
    });
  });

  group('SplitIds', () {
    test('the same inputs give the same id', () {
      expect(SplitIds.part('e1', 'm1'), SplitIds.part('e1', 'm1'));
      expect(
        SplitIds.expenseContact('e1', 'c1'),
        SplitIds.expenseContact('e1', 'c1'),
      );
    });

    test('different inputs give different ids', () {
      expect(SplitIds.part('e1', 'm1'), isNot(SplitIds.part('e1', 'm2')));
      expect(SplitIds.part('e1', 'm1'), isNot(SplitIds.part('e2', 'm1')));
    });

    test("the user's member id differs from a friend's", () {
      expect(SplitIds.member('g', null), isNot(SplitIds.member('g', 'c')));
    });

    test('every derived id of an expense is distinct', () {
      final String share = SplitIds.expenseShare('e1');
      final String balance = SplitIds.expenseBalance('e1');
      final String contact = SplitIds.expenseContact('e1', 'c1');
      expect(share, isNot(balance));
      expect(share, isNot(contact));
      expect(balance, isNot(contact));
    });

    test('settlement ids are distinct and stable', () {
      expect(SplitIds.settlementKhata('s1'), SplitIds.settlementKhata('s1'));
      expect(
        SplitIds.settlementKhata('s1'),
        isNot(SplitIds.settlementAccount('s1')),
      );
      expect(
        SplitIds.settlementKhata('s1'),
        isNot(SplitIds.settlementKhata('s2')),
      );
    });
  });

  group('friendNets', () {
    test('the dinner of the spec gives Amit 200, Neha 200, Rahul 100', () {
      expect(
        SplitCalculator.friendNets(
          total: d('1200'),
          meId: 'me',
          paid: {
            'me': d('800'),
            'rahul': d('400'),
            'amit': d('0'),
            'neha': d('0'),
          },
          shares: {
            'me': d('300'),
            'rahul': d('300'),
            'amit': d('300'),
            'neha': d('300'),
          },
        ),
        {'amit': d('200'), 'neha': d('200'), 'rahul': d('100')},
      );
    });

    test('a friend who paid everything owes the user their share', () {
      expect(
        SplitCalculator.friendNets(
          total: d('1200'),
          meId: 'me',
          paid: {'rahul': d('1200'), 'amit': d('0'), 'neha': d('0')},
          shares: {
            'me': d('300'),
            'rahul': d('300'),
            'amit': d('300'),
            'neha': d('300'),
          },
        ),
        {'amit': d('0'), 'neha': d('0'), 'rahul': d('-300')},
      );
    });

    test('rounding keeps the sum at paid_me − share_me exactly', () {
      final Map<String, Decimal> nets = SplitCalculator.friendNets(
        total: d('100'),
        meId: 'me',
        paid: {'me': d('100'), 'amit': d('0'), 'neha': d('0')},
        shares: {'me': d('33.34'), 'amit': d('33.33'), 'neha': d('33.33')},
      );
      final Decimal sum = nets.values.fold(
        Decimal.zero,
        (Decimal a, Decimal b) => a + b,
      );
      expect(sum, d('100') - d('33.34'));
    });
  });

  group('userRows', () {
    test('the dinner of the spec: share 300, paid for others 500', () {
      final SplitUserRows rows = SplitCalculator.userRows(
        total: d('1200'),
        meId: 'me',
        paid: {
          'me': d('800'),
          'rahul': d('400'),
          'amit': d('0'),
          'neha': d('0'),
        },
        shares: {
          'me': d('300'),
          'rahul': d('300'),
          'amit': d('300'),
          'neha': d('300'),
        },
      );
      expect(rows.expenseShare, d('300'));
      expect(rows.balanceAmount, d('500'));
      expect(rows.balanceIsPaidForOthers, isTrue);
      expect(rows.contactNets, {
        'amit': d('200'),
        'neha': d('200'),
        'rahul': d('100'),
      });
    });

    test('a friend who paid everything: the user owes their share', () {
      final SplitUserRows rows = SplitCalculator.userRows(
        total: d('1200'),
        meId: 'me',
        paid: {'rahul': d('1200'), 'amit': d('0'), 'neha': d('0')},
        shares: {
          'me': d('300'),
          'rahul': d('300'),
          'amit': d('300'),
          'neha': d('300'),
        },
      );
      expect(rows.expenseShare, d('300'));
      expect(rows.balanceAmount, d('300'));
      expect(rows.balanceIsPaidForOthers, isFalse);
      expect(rows.contactNets, {
        'amit': d('0'),
        'neha': d('0'),
        'rahul': d('-300'),
      });
    });

    test('a user who paid for others with no own share', () {
      final SplitUserRows rows = SplitCalculator.userRows(
        total: d('600'),
        meId: 'me',
        paid: {'me': d('600')},
        shares: {'me': d('0'), 'amit': d('600')},
      );
      expect(rows.expenseShare, d('0'));
      expect(rows.balanceAmount, d('600'));
      expect(rows.balanceIsPaidForOthers, isTrue);
      expect(rows.contactNets, {'amit': d('600')});
    });

    test('a user not involved in the expense has no rows', () {
      final SplitUserRows rows = SplitCalculator.userRows(
        total: d('100'),
        meId: 'me',
        paid: {'amit': d('100')},
        shares: {'neha': d('100')},
      );
      expect(rows.expenseShare, d('0'));
      expect(rows.balanceAmount, d('0'));
      expect(rows.balanceIsPaidForOthers, isFalse);
      expect(rows.contactNets, {'amit': d('0'), 'neha': d('0')});
    });

    test('the account movement is always −paid_me and khata nets add up', () {
      final Random random = Random(11);
      const List<String> ids = ['me', 'amit', 'neha', 'rahul', 'sanjay'];
      for (int i = 0; i < 300; i++) {
        final int memberCount = 2 + random.nextInt(4);
        final List<String> members = ids.take(memberCount).toList();
        final Decimal total = SplitCalculator.fromPaise(
          BigInt.from(1 + random.nextInt(999999)),
        );
        final Map<String, Decimal> paid = SplitCalculator.allocate(total, {
          for (final String m in members)
            m: m == members.first
                ? Decimal.parse('${1 + random.nextInt(1000)}')
                : Decimal.parse('${random.nextInt(1001)}'),
        });
        final Map<String, Decimal> shares = SplitCalculator.allocate(total, {
          for (final String m in members)
            m: m == members.first
                ? Decimal.parse('${random.nextInt(1001)}')
                : Decimal.parse('${random.nextInt(1001)}'),
        });
        final SplitUserRows rows = SplitCalculator.userRows(
          total: total,
          meId: 'me',
          paid: paid,
          shares: shares,
        );
        final Decimal netSum = rows.contactNets.values.fold(
          Decimal.zero,
          (Decimal a, Decimal b) => a + b,
        );
        final Decimal paidMe = paid['me'] ?? Decimal.zero;
        final Decimal shareMe = shares['me'] ?? Decimal.zero;
        expect(netSum, paidMe - shareMe, reason: 'case $i nets');
        final Decimal accountMove =
            -rows.expenseShare -
            (rows.balanceIsPaidForOthers
                ? rows.balanceAmount
                : -rows.balanceAmount);
        expect(accountMove, -paidMe, reason: 'case $i account');
      }
    });
  });
}
