import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/views/transaction_list_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../helpers/fake_finance.dart';

void main() {
  setUpAll(() => initializeDateFormatting(AppConstants.defaultLocale));
  tearDown(Get.reset);

  testWidgets('rows pick up category names that load after the rows', (
    WidgetTester tester,
  ) async {
    Get.testMode = true;
    final FakeFinance f = FakeFinance()
      ..addAccount('Cash', '0')
      ..addTransaction(
        id: 't1',
        type: TransactionType.expense,
        amount: '50',
        categoryId: 'cat-food',
      );
    final TransactionController c = Get.put(
      TransactionController(
        f.repositories.transactions,
        f.repositories.accounts,
        f.repositories.categories,
        DataChangeNotifier(),
      ),
    );
    await tester.pumpWidget(
      GetMaterialApp(theme: AppTheme.light, home: const TransactionListView()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Food & Dining'), findsOneWidget);

    // Same as the transactions finishing before the lookups on startup.
    c.categories.clear();
    c.categoryIndex.clear();
    await tester.pump();
    expect(find.text('Food & Dining'), findsNothing);

    c.categories.assignAll(f.categories);
    c.categoryIndex.assignAll(f.categories);
    await tester.pump();
    expect(find.text('Food & Dining'), findsOneWidget);
  });

  testWidgets('rows keep the category name after it is turned off or deleted', (
    WidgetTester tester,
  ) async {
    Get.testMode = true;
    final FakeFinance f = FakeFinance()
      ..addAccount('Cash', '0')
      ..addTransaction(
        id: 't1',
        type: TransactionType.expense,
        amount: '30',
        categoryId: 'cat-inactive',
      )
      ..addTransaction(
        id: 't2',
        type: TransactionType.expense,
        amount: '20',
        categoryId: 'cat-gone',
      );
    // Two categories older transactions still point at: one switched off in
    // the category manager, one deleted. Neither reaches pickers any more,
    // but the rows must not lose their label.
    f.categories.addAll(<Category>[
      Category(
        id: 'cat-inactive',
        name: 'Old Hobby',
        type: CategoryType.expense,
        icon: 'hobby',
        isSystem: false,
        isActive: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      Category(
        id: 'cat-gone',
        name: 'Deleted Plan',
        type: CategoryType.expense,
        icon: 'plan',
        isSystem: false,
        isActive: true,
        deletedAt: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ]);
    Get.put(
      TransactionController(
        f.repositories.transactions,
        f.repositories.accounts,
        f.repositories.categories,
        DataChangeNotifier(),
      ),
    );
    await tester.pumpWidget(
      GetMaterialApp(theme: AppTheme.light, home: const TransactionListView()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Old Hobby'), findsOneWidget);
    expect(find.text('Deleted Plan'), findsOneWidget);
  });
}
