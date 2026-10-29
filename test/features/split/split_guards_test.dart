import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:finance_tracker/features/contacts/controller/contact_detail_controller.dart';
import 'package:finance_tracker/features/contacts/views/contact_detail_view.dart';
import 'package:finance_tracker/features/split/controllers/split_expense_controller.dart';
import 'package:finance_tracker/features/split/views/split_expense_form_view.dart';
import 'package:finance_tracker/features/split/views/split_group_list_view.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/views/transaction_detail_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';
import 'split_group_views_test.dart' show contact, dinner;

/// Goa with the spec dinner, its derived rows, plus a plain transaction, a
/// plain khata entry and a contact in no group.
Future<FakeFinance> guarded() async {
  final FakeFinance f = await dinner(withDerivedRows: true);
  f.contacts.add(contact('c-other', 'Zoya'));
  f.addTransaction(
    id: 'plain-tx',
    type: TransactionType.expense,
    amount: '250',
    categoryId: 'cat-food',
    note: 'Solo lunch',
  );
  f.contactTransactions.add(
    ContactTransaction(
      id: 'plain-entry',
      userId: 'u',
      contactId: 'c-other',
      type: ContactTransactionType.credit,
      amount: Decimal.parse('120'),
      transactionDate: DateTime(2026, 10, 26),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  );
  return f;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  group('guards', () {
    test(
      'deleting a live group member is refused with the group name',
      () async {
        Get.testMode = true;
        final FakeFinance f = await guarded();
        final ContactDetailController controller = ContactDetailController(
          f.repositories.contacts,
          f.repositories.transactions,
          DataChangeNotifier(),
          'c-amit',
          splitRepository: f.repositories.split,
        );
        Get.put(controller);
        await controller.load();

        final bool deleted = await controller.deleteContact();
        expect(deleted, isFalse);
        expect(
          controller.deletion.error.value,
          'Amit is in the group Goa. Remove them from the group first.',
        );
        expect(f.contacts.any((c) => c.id == 'c-amit'), isTrue);
      },
    );

    test('deleting a contact in no group works', () async {
      Get.testMode = true;
      final FakeFinance f = await guarded();
      final ContactDetailController controller = ContactDetailController(
        f.repositories.contacts,
        f.repositories.transactions,
        DataChangeNotifier(),
        'c-other',
        splitRepository: f.repositories.split,
      );
      Get.put(controller);
      await controller.load();

      expect(await controller.deleteContact(), isTrue);
      expect(
        f.contacts.firstWhere((Contact c) => c.id == 'c-other').deletedAt,
        isNotNull,
      );
    });

    test(
      'deleteTransaction refuses a derived row and deletes nothing',
      () async {
        Get.testMode = true;
        final FakeFinance f = await guarded();
        final TransactionController controller = TransactionController(
          f.repositories.transactions,
          f.repositories.accounts,
          f.repositories.categories,
          DataChangeNotifier(),
          splitRepository: f.repositories.split,
        );
        Get.put(controller);
        await controller.load();

        final bool deleted = await controller.deleteTransaction(
          SplitIds.expenseShare('e1'),
        );
        expect(deleted, isFalse);
        expect(
          controller.deletion.error.value,
          'Open it in the group to change or delete it',
        );
        expect(
          f.transactions.any(
            (Transaction t) =>
                t.id == SplitIds.expenseShare('e1') && t.deletedAt == null,
          ),
          isTrue,
        );

        // A plain transaction still deletes.
        expect(await controller.deleteTransaction('plain-tx'), isTrue);
        expect(
          f.transactions.any(
            (Transaction t) => t.id == 'plain-tx' && t.deletedAt == null,
          ),
          isFalse,
        );
      },
    );

    test(
      'deleteEntry refuses a derived khata row and deletes nothing',
      () async {
        Get.testMode = true;
        final FakeFinance f = await guarded();
        final ContactDetailController controller = ContactDetailController(
          f.repositories.contacts,
          f.repositories.transactions,
          DataChangeNotifier(),
          'c-amit',
          splitRepository: f.repositories.split,
        );
        Get.put(controller);
        await controller.load();

        final bool deleted = await controller.deleteEntry(
          SplitIds.expenseContact('e1', 'c-amit'),
        );
        expect(deleted, isFalse);
        expect(
          controller.deletion.error.value,
          'Open it in the group to change or delete it',
        );
        expect(
          f.contactTransactions.where(
            (ContactTransaction e) =>
                e.id == SplitIds.expenseContact('e1', 'c-amit') &&
                e.deletedAt == null,
          ),
          hasLength(1),
        );
      },
    );
  });

  group('detail screens', () {
    testWidgets('a derived transaction shows Open in group, not Edit/Delete', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await guarded();
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        finance: f,
      );

      unawaited(
        Get.toNamed<void>(
          AppRoutes.transactionDetail,
          arguments: SplitIds.expenseShare('e1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TransactionDetailView), findsOneWidget);
      expect(find.text('Open in group'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);

      // It opens the expense form for the split expense.
      await tester.tap(find.text('Open in group'));
      await tester.pumpAndSettle();
      expect(find.byType(SplitExpenseFormView), findsOneWidget);
      final SplitExpenseController form = Get.find<SplitExpenseController>();
      expect(form.members, isNotEmpty);
    });

    testWidgets('a normal transaction keeps Edit and Delete', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await guarded();
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        finance: f,
      );

      unawaited(
        Get.toNamed<void>(AppRoutes.transactionDetail, arguments: 'plain-tx'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open in group'), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
      // The list builds lazily; scroll the delete button into view.
      final Finder list = find
          .descendant(
            of: find.byType(TransactionDetailView),
            matching: find.byType(ListView),
          )
          .first;
      for (int i = 0; i < 10 && find.text('Delete').evaluate().isEmpty; i++) {
        await tester.drag(list, const Offset(0, -250));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('the khata ledger shows the group chip on derived rows only', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await guarded();
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        finance: f,
      );

      unawaited(
        Get.toNamed<void>(AppRoutes.contactDetail, arguments: 'c-amit'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ContactDetailView), findsOneWidget);
      // The one derived entry carries the group chip.
      expect(find.text('Goa'), findsOneWidget);
    });

    testWidgets(
      'the transaction list shows the group chip on derived rows only',
      (WidgetTester tester) async {
        final FakeFinance f = await guarded();
        await pumpApp(
          tester,
          auth: FakeAuthRepository(signedIn: true),
          finance: f,
        );

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.byIcon(Icons.receipt_long_outlined),
          ),
        );
        await tester.pumpAndSettle();

        // The two derived rows (the user's share and the balance) are chipped;
        // the plain one is not, and neither is the Groups action's tooltip.
        expect(find.text('Goa'), findsNWidgets(2));
        expect(find.byType(SplitGroupListView), findsNothing);
      },
    );
  });
}
