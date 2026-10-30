import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:finance_tracker/features/split/controllers/split_group_controller.dart';
import 'package:finance_tracker/features/split/controllers/split_group_detail_controller.dart';
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

  /// A group with the spec dinner saved in it.
  Future<FakeFinance> dinner() async {
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
    final String meId = SplitIds.member('g1', null);
    final String amitId = SplitIds.member('g1', 'c-amit');
    final String nehaId = SplitIds.member('g1', 'c-neha');
    final String rahulId = SplitIds.member('g1', 'c-rahul');
    await f.repositories.split.saveExpense(
      expense: SplitExpense(
        id: 'e1',
        userId: '',
        groupId: 'g1',
        title: 'Dinner',
        totalAmount: Decimal.parse('1200'),
        expenseDate: now,
        splitMode: SplitMode.equal,
        categoryId: 'cat',
        accountId: 'acc',
        createdAt: now,
        updatedAt: now,
      ),
      parts: <SplitPart>[
        SplitPart(
          id: '',
          userId: '',
          splitExpenseId: 'e1',
          memberId: meId,
          paidAmount: Decimal.parse('800'),
          shareAmount: Decimal.parse('300'),
          createdAt: now,
          updatedAt: now,
        ),
        SplitPart(
          id: '',
          userId: '',
          splitExpenseId: 'e1',
          memberId: amitId,
          paidAmount: Decimal.zero,
          shareAmount: Decimal.parse('300'),
          createdAt: now,
          updatedAt: now,
        ),
        SplitPart(
          id: '',
          userId: '',
          splitExpenseId: 'e1',
          memberId: nehaId,
          paidAmount: Decimal.zero,
          shareAmount: Decimal.parse('300'),
          createdAt: now,
          updatedAt: now,
        ),
        SplitPart(
          id: '',
          userId: '',
          splitExpenseId: 'e1',
          memberId: rahulId,
          paidAmount: Decimal.parse('400'),
          shareAmount: Decimal.parse('300'),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    return f;
  }

  group('SplitGroupController', () {
    test('load fills the groups with their nets and the contacts', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await dinner();
      final SplitGroupController controller = SplitGroupController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(controller);
      await controller.load();

      expect(controller.groups.length, 1);
      expect(controller.groups.single.group.name, 'Goa');
      expect(controller.groups.single.memberCount, 4);
      expect(controller.groups.single.userNet, Decimal.parse('500'));
      expect(controller.contacts.length, 3);
    });

    test('a failed load sets the error', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = FakeFinance();
      f.nextError = const NetworkFailure();
      final SplitGroupController controller = SplitGroupController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(controller);
      await controller.load();
      expect(controller.error.value, const NetworkFailure().message);
    });

    test('saveGroup creates the group and reloads', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = FakeFinance();
      f.contacts.add(contact('c1', 'Amit'));
      f.contacts.add(contact('c2', 'Neha'));
      final SplitGroupController controller = SplitGroupController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(controller);
      await controller.load();

      final bool ok = await controller.saveGroup(
        groupId: SplitGroupController.newId(),
        name: 'Trip',
        friendContactIds: <String>['c1', 'c2'],
      );
      expect(ok, isTrue);
      await controller.load();
      expect(controller.groups.length, 1);
      expect(controller.groups.single.memberCount, 3);
    });

    test('a blank name shows the repository message in save.error', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = FakeFinance();
      f.contacts.add(contact('c1', 'Amit'));
      final SplitGroupController controller = SplitGroupController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(controller);
      await controller.load();

      final bool ok = await controller.saveGroup(
        groupId: SplitGroupController.newId(),
        name: '   ',
        friendContactIds: <String>['c1'],
      );
      expect(ok, isFalse);
      expect(controller.save.error.value, 'Give the group a name');
      expect(controller.groups, isEmpty);
    });

    test('deleteImpact counts and deleteGroup removes', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await dinner();
      // The derived rows are not produced by the fake; add them as the real
      // repository would, so the impact counts them.
      f.transactions.addAll(<Transaction>[
        Transaction(
          id: 't-share',
          userId: '',
          accountId: 'acc',
          type: TransactionType.expense,
          amount: Decimal.parse('300'),
          transactionDate: now,
          splitExpenseId: 'e1',
          createdAt: now,
          updatedAt: now,
        ),
        Transaction(
          id: 't-balance',
          userId: '',
          accountId: 'acc',
          type: TransactionType.payment_made,
          amount: Decimal.parse('500'),
          transactionDate: now,
          splitExpenseId: 'e1',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      f.contactTransactions.addAll(<ContactTransaction>[
        for (final String c in <String>['c-amit', 'c-neha', 'c-rahul'])
          ContactTransaction(
            id: 'ct-$c',
            userId: '',
            contactId: c,
            type: ContactTransactionType.credit,
            amount: Decimal.parse('100'),
            transactionDate: now,
            splitExpenseId: 'e1',
            createdAt: now,
            updatedAt: now,
          ),
      ]);
      final SplitGroupController controller = SplitGroupController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(controller);
      await controller.load();

      final ({int expenses, int khataEntries}) impact = await controller
          .deleteImpact('g1');
      expect(impact.expenses, 1);
      expect(impact.khataEntries, 5);

      final bool ok = await controller.deleteGroup('g1');
      expect(ok, isTrue);
      await controller.load();
      expect(controller.groups, isEmpty);
    });

    test('a deleted contact shows as Deleted contact', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await dinner();
      // Amit's contact was deleted on another device and pulled as a
      // tombstone: getContacts no longer returns it.
      f.contacts[0] = Contact(
        id: f.contacts[0].id,
        userId: f.contacts[0].userId,
        name: f.contacts[0].name,
        mobile: f.contacts[0].mobile,
        email: f.contacts[0].email,
        address: f.contacts[0].address,
        notes: f.contacts[0].notes,
        openingBalance: f.contacts[0].openingBalance,
        openingBalanceType: f.contacts[0].openingBalanceType,
        createdAt: f.contacts[0].createdAt,
        updatedAt: f.contacts[0].updatedAt,
        deletedAt: now,
      );
      final SplitGroupController controller = SplitGroupController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
      );
      Get.put(controller);
      await controller.load();

      expect(controller.contactName('c-amit'), 'Deleted contact');
      expect(controller.contactName(null), 'You');
      // The nets are unchanged.
      expect(controller.groups.single.userNet, Decimal.parse('500'));
    });
  });

  group('SplitGroupDetailController', () {
    test('load fills the header numbers and the first page', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await dinner();
      final SplitGroupDetailController controller = SplitGroupDetailController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
        'g1',
      );
      Get.put(controller);
      await controller.load();

      expect(controller.detail.value!.totalSpent, Decimal.parse('1200'));
      expect(controller.detail.value!.userShareTotal, Decimal.parse('300'));
      expect(
        controller.detail.value!.balances.netOf(SplitIds.member('g1', null)),
        Decimal.parse('500'),
      );
      expect(controller.activity.length, 1);
      expect(controller.hasMore, isFalse);
      expect(
        controller.memberNameById(SplitIds.member('g1', 'c-amit')),
        'Amit',
      );
      expect(controller.memberNameById(SplitIds.member('g1', null)), 'You');
    });

    test('outstanding knows who owes whom', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await dinner();
      final SplitGroupDetailController controller = SplitGroupDetailController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
        'g1',
      );
      Get.put(controller);
      await controller.load();

      final String meId = SplitIds.member('g1', null);
      final String amitId = SplitIds.member('g1', 'c-amit');
      expect(controller.outstanding(amitId, meId), Decimal.parse('200'));
      expect(controller.outstanding(meId, amitId), Decimal.zero);
    });

    test('loadMore pages through 120 activity items', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await dinner();
      for (int i = 0; i < 119; i++) {
        await f.repositories.split.saveExpense(
          expense: SplitExpense(
            id: 'ex-$i',
            userId: '',
            groupId: 'g1',
            title: 'Auto $i',
            totalAmount: Decimal.parse('10'),
            expenseDate: DateTime(2026, 1, 1).add(Duration(days: i)),
            splitMode: SplitMode.equal,
            categoryId: 'cat',
            accountId: 'acc',
            createdAt: now,
            updatedAt: now,
          ),
          parts: const <SplitPart>[],
        );
      }
      final SplitGroupDetailController controller = SplitGroupDetailController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
        'g1',
      );
      Get.put(controller);
      await controller.load();
      expect(controller.activity.length, 50);
      expect(controller.hasMore, isTrue);

      await controller.loadMore();
      expect(controller.activity.length, 100);
      expect(controller.hasMore, isTrue);

      await controller.loadMore();
      expect(controller.activity.length, 120);
      expect(controller.hasMore, isFalse);
    });

    test('deleteGroup removes the group', () async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = await dinner();
      final SplitGroupDetailController controller = SplitGroupDetailController(
        f.repositories.split,
        f.repositories.contacts,
        DataChangeNotifier(),
        'g1',
      );
      Get.put(controller);
      await controller.load();

      final bool ok = await controller.deleteGroup();
      expect(ok, isTrue);
      expect((await f.repositories.split.getGroups()), isEmpty);
    });
  });
}
