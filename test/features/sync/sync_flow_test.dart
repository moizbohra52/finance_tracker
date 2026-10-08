import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/contact_datasource.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ConnectivityService connectivity;
  late DataChangeNotifier notifier;
  late SyncEngine syncEngine;
  late AccountRepository accountRepo;
  late TransactionRepository transactionRepo;
  late ContactRepository contactRepo;

  late SupabaseClient dummyClient;

  setUp(() async {
    dummyClient = SupabaseClient('https://dummy.supabase.co', 'dummy-anon-key');
    database = await AppDatabase.inMemory();
    connectivity = ConnectivityService.forTest(
      watch: () => const Stream<NetworkStatus>.empty(),
      check: () async => NetworkStatus.online,
    );
    notifier = DataChangeNotifier();
    syncEngine = SyncEngine(
      database: database,
      client: dummyClient,
      connectivity: connectivity,
      notifier: notifier,
    );
    accountRepo = AccountRepository(
      dummyClient,
      database: database,
      syncEngine: syncEngine,
    );
    transactionRepo = TransactionRepository(
      dummyClient,
      database: database,
      syncEngine: syncEngine,
    );
    contactRepo = ContactRepository(
      ContactLocalDatasourceImpl(database, syncEngine),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'End-to-End Offline Sync Flow: offline writes -> restart -> reconnect -> sync -> idempotency',
    () async {
      // 1. Setup base account and contact
      final Account account = Account(
        id: 'acc-e2e-1',
        userId: 'user-e2e',
        name: 'Main Wallet',
        type: AccountType.cash,
        openingBalance: Decimal.parse('5000.00'),
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await accountRepo.createAccount(account);

      final Contact contact = Contact(
        id: 'contact-e2e-1',
        userId: 'user-e2e',
        name: 'Anil Kumar',
        openingBalance: Decimal.zero,
        openingBalanceType: 'receivable',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await contactRepo.createContact(contact);

      // 2. Disable internet
      connectivity.status.value = NetworkStatus.offline;
      expect(connectivity.isOffline, isTrue);

      // 3. Create income
      final Transaction incomeTx = Transaction(
        id: 'tx-income-offline-1',
        userId: 'user-e2e',
        accountId: 'acc-e2e-1',
        type: TransactionType.income,
        amount: Decimal.parse('1000.00'),
        transactionDate: DateTime(2026, 10, 8, 10, 30),
        note: 'Offline Consulting Income',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await transactionRepo.createTransaction(incomeTx);

      // 4. Create expense
      final Transaction expenseTx = Transaction(
        id: 'tx-expense-offline-1',
        userId: 'user-e2e',
        accountId: 'acc-e2e-1',
        type: TransactionType.expense,
        amount: Decimal.parse('250.00'),
        transactionDate: DateTime(2026, 10, 8, 11, 0),
        note: 'Lunch at Cafe',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await transactionRepo.createTransaction(expenseTx);

      // 5. Create Khata transaction
      final ContactTransaction khataTx = ContactTransaction(
        id: 'khata-offline-credit-1',
        userId: 'user-e2e',
        contactId: 'contact-e2e-1',
        type: ContactTransactionType.credit,
        amount: Decimal.parse('500.00'),
        transactionDate: DateTime(2026, 10, 8, 12, 0),
        note: 'Given cash advance',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await contactRepo.createContactTransaction(khataTx);

      // Verify all transactions appear locally immediately while offline
      final List<Transaction> localTxs = await transactionRepo
          .getTransactions();
      expect(localTxs.length, equals(2));
      expect(localTxs.any((t) => t.id == 'tx-income-offline-1'), isTrue);
      expect(localTxs.any((t) => t.id == 'tx-expense-offline-1'), isTrue);

      final List<ContactTransaction> localKhata = await contactRepo
          .getContactTransactions('contact-e2e-1');
      expect(localKhata.length, equals(1));
      expect(localKhata.first.id, equals('khata-offline-credit-1'));

      // Check pending queue count: 2 initial + 3 offline = 5 operations
      final int queueCountOffline = await database.getPendingQueueCount();
      expect(queueCountOffline, equals(5));

      // 6. Simulate app close and reopen with persistent DB
      final AppDatabase reopenedDb = AppDatabase(database: database.db);
      final SyncEngine reopenedEngine = SyncEngine(
        database: reopenedDb,
        client: dummyClient,
        connectivity: connectivity,
        notifier: notifier,
      );
      final TransactionRepository reopenedTxRepo = TransactionRepository(
        dummyClient,
        database: reopenedDb,
        syncEngine: reopenedEngine,
      );
      final ContactRepository reopenedContactRepo = ContactRepository(
        ContactLocalDatasourceImpl(reopenedDb, reopenedEngine),
      );

      // Verify all offline data survived restart
      final List<Transaction> reopenedTxs = await reopenedTxRepo
          .getTransactions();
      expect(reopenedTxs.length, equals(2));

      final List<ContactTransaction> reopenedKhata = await reopenedContactRepo
          .getContactTransactions('contact-e2e-1');
      expect(reopenedKhata.length, equals(1));

      final List<SyncQueueItem> pendingQueue = await reopenedEngine
          .getPendingItems();
      expect(pendingQueue.length, equals(5));

      // 7. Re-enable internet
      connectivity.status.value = NetworkStatus.online;
      expect(connectivity.isOffline, isFalse);

      // 8. Simulate successful server upload
      // For every item in queue, mark status synced and update entity sync_status
      for (final SyncQueueItem item in pendingQueue) {
        await reopenedDb.updateQueueItemStatus(
          id: item.id!,
          status: SyncItemStatus.synced,
        );
        await reopenedDb.markEntitySynced(item.entity, item.entityId);
      }

      // Clean up synced items
      await reopenedDb.clearSyncedQueueItems();
      expect(await reopenedDb.getPendingQueueCount(), equals(0));

      // 9. Verify no duplicate records on repeated retries (idempotency)
      // Retrying create with onlyIfAbsent or same ID
      await reopenedTxRepo.createTransaction(incomeTx, onlyIfAbsent: true);
      final List<Transaction> finalTxs = await reopenedTxRepo.getTransactions();
      expect(finalTxs.length, equals(2)); // No duplicates created!
      expect(await reopenedDb.getPendingQueueCount(), equals(0));
    },
  );
}
