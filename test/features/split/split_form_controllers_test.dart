import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:finance_tracker/features/split/controllers/split_expense_controller.dart';
import 'package:finance_tracker/features/split/controllers/split_settlement_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime now = DateTime(2026, 10, 26, 12);

  Contact contact(String id, String name) => Contact(
    id: id,
    userId: 'u',
    name: name,
    openingBalance: Decimal.zero,
    openingBalanceType: 'receivable',
    createdAt: now,
    updatedAt: now,
  );

  Future<FakeFinance> makeGroup() async {
    final FakeFinance f = FakeFinance();
    f.contacts.addAll(<Contact>[
      contact('c-amit', 'Amit'),
      contact('c-neha', 'Neha'),
      contact('c-rahul', 'Rahul'),
    ]);
    await f.repositories.split.saveGroup(
      groupId: 'g1',
      name: 'Goa',
      friendContactIds: <String>['c-amit', 'c-neha', 'c-rahul'],
    );
    return f;
  }

  group('SplitExpenseController', () {
    test('the spec dinner is valid and previews share 300, get 500', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitExpenseController c = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');

      c.totalText.value = '1200';
      c.multiplePayers.value = true;
      final String meId = SplitIds.member('g1', null);
      final String rahulId = SplitIds.member('g1', 'c-rahul');
      c.paidText[meId] = '800';
      c.paidText[rahulId] = '400';
      c.ticked.addAll(c.members.map((SplitMember m) => m.id));
      c.categoryId.value = 'cat';
      c.accountId.value = 'acc';

      expect(c.error, isNull);
      expect(c.preview!.yourShare, Decimal.parse('300'));
      expect(c.preview!.youGet, Decimal.parse('500'));

      final bool ok = await c.saveExpense(
        id: SplitExpenseController.newId(),
        title: 'Dinner',
        date: now,
        note: null,
      );
      expect(ok, isTrue);
      expect(f.splitExpenses.single.totalAmount, Decimal.parse('1200'));
      expect(f.splitParts.length, 4);
    });

    test('paidLeft shows what is still unassigned', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitExpenseController c = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');

      c.totalText.value = '1200';
      c.multiplePayers.value = true;
      c.paidText[SplitIds.member('g1', null)] = '800';
      expect(c.paidLeft, Decimal.parse('400'));
    });

    test('three decimals are refused and nothing is stored', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitExpenseController c = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');

      c.totalText.value = '100.005';
      c.multiplePayers.value = true;
      c.paidText[SplitIds.member('g1', null)] = '100.005';
      c.ticked.addAll(c.members.map((SplitMember m) => m.id));
      c.categoryId.value = 'cat';
      c.accountId.value = 'acc';

      expect(c.error, 'Amounts can have at most 2 decimals');
      final bool ok = await c.saveExpense(
        id: SplitExpenseController.newId(),
        title: 'Dinner',
        date: now,
        note: null,
      );
      expect(ok, isFalse);
      expect(f.splitExpenses, isEmpty);
      expect(c.save.error.value, 'Amounts can have at most 2 decimals');
    });

    test('a paid sum one paisa off is refused', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitExpenseController c = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');

      c.totalText.value = '1200';
      c.multiplePayers.value = true;
      c.paidText[SplitIds.member('g1', null)] = '800';
      c.paidText[SplitIds.member('g1', 'c-rahul')] = '399.99';
      c.ticked.addAll(c.members.map((SplitMember m) => m.id));
      c.categoryId.value = 'cat';
      c.accountId.value = 'acc';

      expect(c.error, 'What was paid must add up to the total');
    });

    test('blank cells count as zero', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitExpenseController c = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');

      c.totalText.value = '1200';
      c.multiplePayers.value = true;
      // Only Rahul's paid cell is typed; the rest are blank.
      c.paidText[SplitIds.member('g1', 'c-rahul')] = '1200';
      c.ticked.addAll(c.members.map((SplitMember m) => m.id));
      c.categoryId.value = 'cat';
      c.accountId.value = 'acc';

      expect(c.error, isNull);
      final bool ok = await c.saveExpense(
        id: SplitExpenseController.newId(),
        title: 'Dinner',
        date: now,
        note: null,
      );
      expect(ok, isTrue);
      expect(f.splitParts.length, 4);
    });

    test('a user who paid for others needs no category', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitExpenseController c = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');

      c.totalText.value = '1200';
      // Single payer: the user. Only Amit and Neha share it.
      c.ticked
        ..clear()
        ..addAll(<String>[
          SplitIds.member('g1', 'c-amit'),
          SplitIds.member('g1', 'c-neha'),
        ]);
      c.accountId.value = 'acc';

      expect(c.categoryId.value, isNull);
      expect(c.error, isNull);
    });

    test('percent inputs and a mode switch keep the typed amounts', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitExpenseController c = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');

      c.totalText.value = '100';
      c.mode.value = SplitMode.percent;
      c.inputText[SplitIds.member('g1', null)] = '50';
      c.inputText[SplitIds.member('g1', 'c-amit')] = '30';
      c.inputText[SplitIds.member('g1', 'c-neha')] = '20';
      c.categoryId.value = 'cat';
      c.accountId.value = 'acc';

      expect(c.error, isNull);
      expect(c.shares[SplitIds.member('g1', null)], Decimal.parse('50'));
      expect(c.sharesLeft, Decimal.zero);

      c.mode.value = SplitMode.shares;
      expect(c.inputText[SplitIds.member('g1', null)], '50');
      c.inputText[SplitIds.member('g1', 'c-neha')] = '2';
      c.inputText[SplitIds.member('g1', 'c-amit')] = '1';
      c.inputText[SplitIds.member('g1', null)] = '1';
      expect(c.error, isNull);
      expect(c.shares[SplitIds.member('g1', 'c-neha')], Decimal.parse('50'));
    });

    test('editing prefills mode, inputs and paid cells', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitExpenseController c = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');
      c.totalText.value = '100';
      c.mode.value = SplitMode.percent;
      c.inputText[SplitIds.member('g1', null)] = '50';
      c.inputText[SplitIds.member('g1', 'c-amit')] = '50';
      c.multiplePayers.value = true;
      c.paidText[SplitIds.member('g1', null)] = '50';
      c.paidText[SplitIds.member('g1', 'c-amit')] = '50';
      c.categoryId.value = 'cat';
      c.accountId.value = 'acc';
      final String id = SplitExpenseController.newId();
      expect(
        await c.saveExpense(id: id, title: 'Auto', date: now, note: null),
        isTrue,
      );

      final SplitExpenseController edit = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(edit);
      await edit.start(
        groupId: 'g1',
        existing: await f.repositories.split.getExpense(id),
      );

      expect(edit.mode.value, SplitMode.percent);
      expect(edit.totalText.value, '100');
      expect(edit.inputText[SplitIds.member('g1', null)], '50');
      expect(edit.paidText[SplitIds.member('g1', 'c-amit')], '50');
      expect(edit.categoryId.value, 'cat');
      expect(edit.accountId.value, 'acc');
      expect(edit.error, isNull);
    });
  });

  group('SplitSettlementController', () {
    Future<SplitExpenseController> savedDinner(FakeFinance f) async {
      final SplitExpenseController c = SplitExpenseController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.categories,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');
      c.totalText.value = '1200';
      c.multiplePayers.value = true;
      c.paidText[SplitIds.member('g1', null)] = '800';
      c.paidText[SplitIds.member('g1', 'c-rahul')] = '400';
      c.ticked.addAll(c.members.map((SplitMember m) => m.id));
      c.categoryId.value = 'cat';
      c.accountId.value = 'acc';
      expect(
        await c.saveExpense(
          id: SplitExpenseController.newId(),
          title: 'Dinner',
          date: now,
          note: null,
        ),
        isTrue,
      );
      return c;
    }

    test('prefills the outstanding amount for amit→me', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      await savedDinner(f);
      final SplitSettlementController c = SplitSettlementController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(
        groupId: 'g1',
        fromMemberId: SplitIds.member('g1', 'c-amit'),
        toMemberId: SplitIds.member('g1', null),
      );

      expect(c.amountText.value, '200');
      expect(c.userIsParty, isTrue);
    });

    test('overpaying is allowed', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      await savedDinner(f);
      final SplitSettlementController c = SplitSettlementController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(
        groupId: 'g1',
        fromMemberId: SplitIds.member('g1', 'c-amit'),
        toMemberId: SplitIds.member('g1', null),
      );
      c.amountText.value = '250';
      c.accountId.value = 'acc';

      final bool ok = await c.saveSettlement(
        id: SplitSettlementController.newId(),
        date: now,
        note: null,
      );
      expect(ok, isTrue);
      expect(f.splitSettlements.single.amount, Decimal.parse('250'));
    });

    test('from == to is refused', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitSettlementController c = SplitSettlementController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');
      c.fromId.value = SplitIds.member('g1', 'c-amit');
      c.toId.value = SplitIds.member('g1', 'c-amit');
      c.amountText.value = '100';

      final bool ok = await c.saveSettlement(
        id: SplitSettlementController.newId(),
        date: now,
        note: null,
      );
      expect(ok, isFalse);
      expect(c.save.error.value, 'Choose two different people');
    });

    test('an amount of zero is refused', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitSettlementController c = SplitSettlementController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');
      c.fromId.value = SplitIds.member('g1', null);
      c.toId.value = SplitIds.member('g1', 'c-amit');
      c.amountText.value = '0';

      final bool ok = await c.saveSettlement(
        id: SplitSettlementController.newId(),
        date: now,
        note: null,
      );
      expect(ok, isFalse);
      expect(c.save.error.value, 'Amount must be more than zero');
    });

    test('an account is cleared for a friend-to-friend settlement', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await makeGroup();
      final SplitSettlementController c = SplitSettlementController(
        f.repositories.split,
        f.repositories.accounts,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(c);
      await c.start(groupId: 'g1');
      c.fromId.value = SplitIds.member('g1', 'c-amit');
      c.toId.value = SplitIds.member('g1', 'c-rahul');
      c.amountText.value = '100';
      c.accountId.value = 'acc';
      expect(c.userIsParty, isFalse);

      final bool ok = await c.saveSettlement(
        id: SplitSettlementController.newId(),
        date: now,
        note: null,
      );
      expect(ok, isTrue);
      expect(f.splitSettlements.single.accountId, isNull);
    });
  });
}
