import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_finance.dart';

void main() {
  late FakeFinance finance;
  late AccountController controller;

  setUp(() {
    finance = FakeFinance();
    controller = AccountController(
      finance.repositories.accounts,
      finance.repositories.transactions,
      DataChangeNotifier(),
    );
  });

  Future<Account> save({Account? existing, bool? isActive}) async {
    expect(
      await controller.saveAccount(
        id: existing?.id ?? 'acc-1',
        existing: existing,
        name: 'Old wallet',
        type: AccountType.cash,
        openingBalance: Decimal.parse('100'),
        openingBalanceDate: DateTime(2026, 10, 1),
        isActive: isActive,
      ),
      isTrue,
    );
    return finance.accounts.singleWhere((Account a) => a.id == 'acc-1');
  }

  test('an account can be archived and brought back', () async {
    final Account created = await save();
    expect(created.isActive, isTrue);

    final Account archived = await save(existing: created, isActive: false);
    expect(archived.isActive, isFalse);

    // An edit that does not touch the switch keeps the state.
    expect((await save(existing: archived)).isActive, isFalse);

    expect((await save(existing: archived, isActive: true)).isActive, isTrue);
  });
}
