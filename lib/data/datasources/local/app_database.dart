import 'dart:io';

import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Relational SQLite database for offline-first transactional finance data.
class AppDatabase {
  AppDatabase({Database? database}) : _db = database;

  static const String databaseName = 'finance_tracker.db';
  static const int databaseVersion = 1;

  Database? _db;

  Database get db {
    final Database? d = _db;
    if (d == null) {
      throw StateError(
        'AppDatabase is not opened yet. Call AppDatabase.open() first.',
      );
    }
    return d;
  }

  bool get isOpen => _db != null && _db!.isOpen;

  static bool _ffiInitialized = false;

  /// Initializes platform-specific database factory for Desktop and Tests.
  static void initializePlatform() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (!_ffiInitialized) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        _ffiInitialized = true;
      }
    }
  }

  /// Opens the local SQLite database.
  static Future<AppDatabase> open({String? customPath}) async {
    initializePlatform();
    final String path =
        customPath ?? p.join(await getDatabasesPath(), databaseName);
    final Database database = await openDatabase(
      path,
      version: databaseVersion,
      onCreate: (Database db, int version) async {
        await _createTables(db);
        await _seedSystemCategories(db);
      },
    );
    return AppDatabase(database: database);
  }

  /// Creates in-memory database instance for testing.
  static Future<AppDatabase> inMemory() async {
    sqfliteFfiInit();
    final Database database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: (Database db, int version) async {
          await _createTables(db);
          await _seedSystemCategories(db);
        },
      ),
    );
    return AppDatabase(database: database);
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  static Future<void> _createTables(DatabaseExecutor db) async {
    // 1. Accounts
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        opening_balance TEXT NOT NULL,
        opening_balance_date TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_accounts_user ON accounts(user_id);',
    );

    // 2. Categories
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon TEXT NOT NULL,
        is_system INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_categories_user ON categories(user_id);',
    );

    // 3. Transactions
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        account_id TEXT NOT NULL,
        category_id TEXT,
        contact_id TEXT,
        type TEXT NOT NULL,
        amount TEXT NOT NULL,
        transaction_date TEXT NOT NULL,
        note TEXT,
        description TEXT,
        payment_method TEXT,
        attachment_url TEXT,
        transfer_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, transaction_date DESC);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_account ON transactions(account_id);',
    );

    // 4. Contacts
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contacts (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        name TEXT NOT NULL,
        mobile TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        opening_balance TEXT NOT NULL DEFAULT '0',
        opening_balance_type TEXT NOT NULL DEFAULT 'receivable',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_contacts_user ON contacts(user_id);',
    );

    // 5. Contact Transactions
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contact_transactions (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        contact_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount TEXT NOT NULL,
        transaction_date TEXT NOT NULL,
        due_date TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_contact_tx_contact ON contact_transactions(contact_id, transaction_date DESC);',
    );

    // 6. Budgets
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budgets (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        category_id TEXT,
        amount TEXT NOT NULL,
        period_type TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        alert_75 INTEGER NOT NULL DEFAULT 1,
        alert_90 INTEGER NOT NULL DEFAULT 1,
        alert_100 INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_budgets_user ON budgets(user_id);',
    );

    // 7. Recurring Transactions
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_transactions (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        account_id TEXT NOT NULL,
        category_id TEXT,
        type TEXT NOT NULL,
        amount TEXT NOT NULL,
        frequency TEXT NOT NULL,
        interval_count INTEGER NOT NULL DEFAULT 1,
        start_date TEXT NOT NULL,
        end_date TEXT,
        next_run_at TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recurring_user ON recurring_transactions(user_id);',
    );

    // 8. Reminders
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        contact_id TEXT,
        account_id TEXT,
        title TEXT NOT NULL,
        description TEXT,
        transaction_id TEXT,
        reminder_type TEXT,
        amount TEXT,
        remind_at TEXT NOT NULL,
        snoozed_until TEXT,
        repeat_rule TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        notification_enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reminders_user_remind ON reminders(user_id, remind_at);',
    );

    // 9. User Settings
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_settings (
        id TEXT PRIMARY KEY,
        user_id TEXT UNIQUE,
        date_format TEXT,
        number_format TEXT,
        first_day_of_week TEXT,
        language_code TEXT,
        default_account_id TEXT,
        notifications_enabled INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');

    // 10. Profiles (cached for offline)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS profiles (
        id TEXT PRIMARY KEY,
        full_name TEXT,
        mobile TEXT,
        avatar_url TEXT,
        currency_code TEXT DEFAULT 'INR',
        timezone TEXT,
        created_at TEXT,
        updated_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      );
    ''');

    // 11. Sync Queue
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT NOT NULL,
        entity TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_attempt TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status, id);',
    );

    // 12. Sync Metadata
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  static Future<void> _seedSystemCategories(DatabaseExecutor db) async {
    const List<Map<String, dynamic>> seeds = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000101',
        'name': 'Salary',
        'type': 'income',
        'icon': 'salary',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000102',
        'name': 'Business',
        'type': 'income',
        'icon': 'business',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000103',
        'name': 'Freelance',
        'type': 'income',
        'icon': 'freelance',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000104',
        'name': 'Interest',
        'type': 'income',
        'icon': 'interest',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000105',
        'name': 'Gift Received',
        'type': 'income',
        'icon': 'gift',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000106',
        'name': 'Refund',
        'type': 'income',
        'icon': 'refund',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000107',
        'name': 'Other Income',
        'type': 'income',
        'icon': 'other_income',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000201',
        'name': 'Food & Dining',
        'type': 'expense',
        'icon': 'food',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000202',
        'name': 'Groceries',
        'type': 'expense',
        'icon': 'groceries',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000203',
        'name': 'Transport',
        'type': 'expense',
        'icon': 'transport',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000204',
        'name': 'Fuel',
        'type': 'expense',
        'icon': 'fuel',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000205',
        'name': 'Shopping',
        'type': 'expense',
        'icon': 'shopping',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000206',
        'name': 'Rent',
        'type': 'expense',
        'icon': 'rent',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000207',
        'name': 'Bills & Utilities',
        'type': 'expense',
        'icon': 'utilities',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000208',
        'name': 'Mobile & Internet',
        'type': 'expense',
        'icon': 'mobile',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000209',
        'name': 'EMI & Loans',
        'type': 'expense',
        'icon': 'emi',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000210',
        'name': 'Insurance',
        'type': 'expense',
        'icon': 'insurance',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000211',
        'name': 'Health',
        'type': 'expense',
        'icon': 'health',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000212',
        'name': 'Education',
        'type': 'expense',
        'icon': 'education',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000213',
        'name': 'Entertainment',
        'type': 'expense',
        'icon': 'entertainment',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000214',
        'name': 'Travel',
        'type': 'expense',
        'icon': 'travel',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000215',
        'name': 'Subscriptions',
        'type': 'expense',
        'icon': 'subscriptions',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000216',
        'name': 'Personal Care',
        'type': 'expense',
        'icon': 'personal_care',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000217',
        'name': 'Gifts & Donations',
        'type': 'expense',
        'icon': 'donation',
      },
      <String, dynamic>{
        'id': 'c0000000-0000-4000-8000-000000000218',
        'name': 'Other Expense',
        'type': 'expense',
        'icon': 'other_expense',
      },
    ];

    final String now = DateTime.now().toUtc().toIso8601String();
    for (final Map<String, dynamic> seed in seeds) {
      await db.insert('categories', <String, dynamic>{
        'id': seed['id'],
        'user_id': null,
        'name': seed['name'],
        'type': seed['type'],
        'icon': seed['icon'],
        'is_system': 1,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
        'sync_status': 'synced',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // --- Sync Queue Helpers ---

  Future<int> enqueue(SyncQueueItem item) async {
    return await db.insert('sync_queue', item.toRow());
  }

  Future<List<SyncQueueItem>> getPendingQueue({int limit = 50}) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'sync_queue',
      where: "status IN ('pending', 'failed')",
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(SyncQueueItem.fromRow).toList();
  }

  Future<int> getPendingQueueCount() async {
    final List<Map<String, dynamic>> res = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM sync_queue WHERE status IN ('pending', 'failed')",
    );
    if (res.isEmpty) return 0;
    return (res.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<void> updateQueueItemStatus({
    required int id,
    required SyncItemStatus status,
    String? errorMessage,
    int? retryCount,
    DateTime? lastAttempt,
  }) async {
    final Map<String, dynamic> values = <String, dynamic>{
      'status': status.name,
      'error_message': ?errorMessage,
      'retry_count': ?retryCount,
      if (lastAttempt != null) 'last_attempt': lastAttempt.toIso8601String(),
    };
    await db.update(
      'sync_queue',
      values,
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  Future<void> removeQueueItem(int id) async {
    await db.delete('sync_queue', where: 'id = ?', whereArgs: <Object>[id]);
  }

  Future<void> clearSyncedQueueItems() async {
    await db.delete('sync_queue', where: "status = 'synced'");
  }

  // --- Sync Metadata Helpers ---

  Future<String?> getMetadata(String key) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'sync_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMetadata(String key, String value) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    await db.insert('sync_metadata', <String, dynamic>{
      'key': key,
      'value': value,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- Entity Sync Status Helper ---

  Future<void> markEntitySynced(String table, String id) async {
    await db.update(
      table,
      <String, dynamic>{'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  Future<bool> hasPendingSyncFor(String table, String id) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'sync_queue',
      columns: <String>['id'],
      where:
          "entity = ? AND entity_id = ? AND status IN ('pending', 'processing')",
      whereArgs: <Object>[table, id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Wipes all non-system data from the database (e.g. for complete reset).
  Future<void> clearAllUserData([String? userId]) async {
    final List<String> userTables = <String>[
      'accounts',
      'transactions',
      'contacts',
      'contact_transactions',
      'budgets',
      'recurring_transactions',
      'reminders',
      'user_settings',
      'profiles',
    ];

    for (final String table in userTables) {
      if (userId != null) {
        final String col = table == 'profiles' ? 'id' : 'user_id';
        await db.delete(table, where: '$col = ?', whereArgs: <Object>[userId]);
      } else {
        await db.delete(table);
      }
    }
    // Delete custom categories
    if (userId != null) {
      await db.delete(
        'categories',
        where: 'user_id = ?',
        whereArgs: <Object>[userId],
      );
    } else {
      await db.delete('categories', where: 'is_system = 0');
    }
    // Clear sync queue
    await db.delete('sync_queue');
  }
}
