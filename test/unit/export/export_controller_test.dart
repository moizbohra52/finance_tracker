import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/export_service.dart';
import 'package:finance_tracker/core/services/file_sharing_service.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/export/controllers/export_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import '../../helpers/fake_finance.dart';

class _FakeSharingService extends FileSharingService {
  String? lastSharedFileName;
  String? lastSharedContent;
  List<int>? lastSharedBytes;

  @override
  Future<ShareResult> saveAndShareString({
    required String fileName,
    required String content,
    String? mimeType,
    String? subject,
  }) async {
    lastSharedFileName = fileName;
    lastSharedContent = content;
    return const ShareResult('success', ShareResultStatus.success);
  }

  @override
  Future<ShareResult> saveAndShareBytes({
    required String fileName,
    required List<int> bytes,
    String? mimeType,
    String? subject,
  }) async {
    lastSharedFileName = fileName;
    lastSharedBytes = bytes;
    return const ShareResult('success', ShareResultStatus.success);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFinance finance;
  late _FakeSharingService fakeSharing;
  late ExportController controller;

  setUp(() {
    finance = FakeFinance();
    fakeSharing = _FakeSharingService();

    // Seed some accounts and categories
    finance.accounts.add(
      Account(
        id: 'acc-1',
        userId: 'u-1',
        name: 'Checking',
        type: AccountType.bank,
        openingBalance: Decimal.parse('1000'),
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    controller = ExportController(
      transactionRepository: finance.repositories.transactions,
      accountRepository: finance.repositories.accounts,
      contactRepository: finance.repositories.contacts,
      budgetRepository: finance.repositories.budgets,
      categoryRepository: finance.repositories.categories,
      sharingService: fakeSharing,
    );
  });

  group('ExportController Date Range Calculations', () {
    test('calculates correct bounds for presets', () {
      controller.datePreset.value = DateRangePreset.all;
      final ({DateTime? start, DateTime? end}) allRange =
          controller.activeDateRange;
      expect(allRange.start, isNull);
      expect(allRange.end, isNull);

      controller.datePreset.value = DateRangePreset.today;
      final ({DateTime? start, DateTime? end}) todayRange =
          controller.activeDateRange;
      expect(todayRange.start, isNotNull);
      expect(todayRange.end, isNotNull);
      expect(todayRange.start!.day, DateTime.now().day);

      controller.datePreset.value = DateRangePreset.thisMonth;
      final ({DateTime? start, DateTime? end}) monthRange =
          controller.activeDateRange;
      expect(monthRange.start!.day, 1);
      expect(monthRange.start!.month, DateTime.now().month);

      // Custom range
      final DateTime customS = DateTime(2026, 5, 1);
      final DateTime customE = DateTime(2026, 5, 15);
      controller.setCustomRange(customS, customE);
      expect(controller.datePreset.value, DateRangePreset.custom);
      expect(controller.activeDateRange.start, customS);
      expect(controller.activeDateRange.end!.day, 15);
    });
  });

  group('ExportController Export Execution', () {
    test(
      'exports transactions with filters and invokes sharing service',
      () async {
        // Add transactions
        finance.transactions.add(
          Transaction(
            id: 'tx-1',
            userId: 'u-1',
            accountId: 'acc-1',
            categoryId: 'cat-food',
            type: TransactionType.expense,
            amount: Decimal.parse('500'),
            transactionDate: DateTime.now(),
            note: 'Lunch at Cafe',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        controller.selectedType.value = ExportType.transactions;
        controller.selectedFormat.value = ExportFormat.csv;
        controller.datePreset.value = DateRangePreset.all;

        await controller.exportAndShare();

        expect(fakeSharing.lastSharedFileName, isNotNull);
        expect(fakeSharing.lastSharedFileName, startsWith('transactions_'));
        expect(fakeSharing.lastSharedFileName, endsWith('.csv'));
        expect(fakeSharing.lastSharedContent, contains('Lunch at Cafe'));
        expect(fakeSharing.lastSharedContent, contains('500.00'));
      },
    );

    test('exports accounts into Excel format', () async {
      controller.selectedType.value = ExportType.accounts;
      controller.selectedFormat.value = ExportFormat.excel;

      await controller.exportAndShare();

      expect(fakeSharing.lastSharedFileName, startsWith('accounts_'));
      expect(fakeSharing.lastSharedFileName, endsWith('.xlsx'));
      expect(fakeSharing.lastSharedBytes, isNotNull);
      expect(fakeSharing.lastSharedBytes!.isNotEmpty, isTrue);
    });
  });
}
