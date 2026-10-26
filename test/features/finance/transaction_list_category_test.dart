import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
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
    await tester.pump();
    expect(find.text('Food & Dining'), findsNothing);

    c.categories.assignAll(f.categories);
    await tester.pump();
    expect(find.text('Food & Dining'), findsOneWidget);
  });
}
