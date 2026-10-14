import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/account_balance_calculator.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime(2026, 10, 14, 12);

TransferLegs _build({
  String from = 'acc-cash',
  String to = 'acc-bank',
  String amount = '300',
  String transferId = 'tr-1',
}) => TransferLegs.build(
  transferId: transferId,
  outgoingId: '$transferId-out',
  incomingId: '$transferId-in',
  fromAccountId: from,
  toAccountId: to,
  amount: Decimal.parse(amount),
  date: _now,
  now: _now,
  note: 'ATM',
);

void main() {
  group('building a transfer', () {
    test('makes one outgoing and one incoming leg sharing an id', () {
      final TransferLegs legs = _build();

      expect(legs.outgoing.type, TransactionType.transfer_out);
      expect(legs.incoming.type, TransactionType.transfer_in);
      expect(legs.outgoing.transferId, 'tr-1');
      expect(legs.incoming.transferId, 'tr-1');
      expect(legs.outgoing.accountId, 'acc-cash');
      expect(legs.incoming.accountId, 'acc-bank');
      expect(legs.outgoing.amount, Decimal.parse('300'));
      expect(legs.incoming.amount, Decimal.parse('300'));
      expect(legs.incoming.note, 'ATM');
      expect(legs.outgoing.categoryId, isNull, reason: 'not income/expense');
    });

    test('refuses the same account on both sides', () {
      expect(() => _build(to: 'acc-cash'), throwsArgumentError);
    });

    test('refuses a zero or negative amount', () {
      expect(() => _build(amount: '0'), throwsArgumentError);
      expect(() => _build(amount: '-5'), throwsArgumentError);
    });

    test('moves money between accounts without changing the total', () {
      final TransferLegs legs = _build();
      final Decimal cash = AccountBalanceCalculator.calculateBalance(
        Decimal.parse('1000'),
        <Transaction>[legs.outgoing],
      );
      final Decimal bank = AccountBalanceCalculator.calculateBalance(
        Decimal.parse('500'),
        <Transaction>[legs.incoming],
      );

      expect(cash, Decimal.parse('700'));
      expect(bank, Decimal.parse('800'));
      expect(cash + bank, Decimal.parse('1500'));
    });
  });

  group('pairing stored rows', () {
    test('finds the two live legs', () {
      final TransferLegs legs = _build();
      final TransferLegs? paired = TransferLegs.fromRows(<Transaction>[
        legs.incoming,
        legs.outgoing,
      ]);

      expect(paired?.fromAccountId, 'acc-cash');
      expect(paired?.toAccountId, 'acc-bank');
    });

    test('is null when a leg is deleted or missing', () {
      final TransferLegs legs = _build();

      expect(
        TransferLegs.fromRows(<Transaction>[
          legs.outgoing,
          legs.incoming.copyWith(deletedAt: _now),
        ]),
        isNull,
      );
      expect(TransferLegs.fromRows(<Transaction>[legs.outgoing]), isNull);
    });
  });

  group('editing in place', () {
    final TransferLegs before = _build();

    test('is allowed for the same accounts or a new destination', () {
      expect(before.canUpdateInPlace('acc-cash'), isTrue);
      expect(before.canUpdateInPlace('acc-card'), isTrue);
    });

    test('is not allowed when the source moves onto the old destination', () {
      // One leg per account per transfer: the outgoing leg would land on the
      // account the incoming leg still holds while the edit syncs.
      expect(before.canUpdateInPlace('acc-bank'), isFalse);
    });
  });
}
