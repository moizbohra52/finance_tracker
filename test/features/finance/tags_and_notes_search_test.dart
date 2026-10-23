import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_finance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recent tags come from the newest notes, once each', () async {
    final FakeFinance f = FakeFinance()..addAccount('Cash', '0');
    final DateTime now = DateTime.now();
    f
      ..addTransaction(
        id: 't1',
        type: TransactionType.expense,
        amount: '10',
        note: 'Old #Goa trip',
        date: now.subtract(const Duration(days: 2)),
      )
      ..addTransaction(
        id: 't2',
        type: TransactionType.expense,
        amount: '10',
        note: 'Lunch #office #goa',
        date: now,
      )
      ..addTransaction(
        id: 't3',
        type: TransactionType.expense,
        amount: '10',
        note: 'no tags',
      );

    final TransactionController c = TransactionController(
      f.repositories.transactions,
      f.repositories.accounts,
      f.repositories.categories,
      DataChangeNotifier(),
    );
    await c.loadLookups();

    expect(c.recentTags, <String>['#office', '#goa']);
  });

  test('khata search also matches contact notes', () async {
    final FakeFinance f = FakeFinance();
    f.contacts.add(
      Contact(
        id: 'c1',
        userId: 'u',
        name: 'Ramesh',
        notes: 'Milk supplier',
        openingBalance: Decimal.zero,
        openingBalanceType: 'receivable',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    final ContactController c = ContactController(
      f.repositories.contacts,
      DataChangeNotifier(),
    );
    await c.load();

    c.searchText.value = 'milk';
    expect(c.visible.single.contact.name, 'Ramesh');
    c.searchText.value = 'bread';
    expect(c.visible, isEmpty);
  });

  test('tagged notes are read from the local database', () async {
    final AppDatabase database = await AppDatabase.inMemory();
    addTearDown(database.close);
    final TransactionRepository repo = TransactionRepository(
      SupabaseClient('https://dummy.supabase.co', 'dummy-anon-key'),
      database: database,
      syncEngine: SyncEngine(database: database),
    );
    for (final (String id, String note) in <(String, String)>[
      ('t1', 'Dinner #goa'),
      ('t2', 'Plain note'),
    ]) {
      await repo.createTransaction(
        Transaction(
          id: id,
          userId: '',
          accountId: 'acc-1',
          type: TransactionType.expense,
          amount: Decimal.parse('10'),
          transactionDate: DateTime(2026, 10, 23),
          note: note,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
    }

    expect(await repo.getTaggedNotes(), <String>['Dinner #goa']);
    expect(
      (await repo.getTransactions(search: '#goa')).single.id,
      't1',
      reason: 'the note search finds a tag',
    );
  });
}
