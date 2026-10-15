import 'dart:developer' as developer;
import 'dart:io';

import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Where each account's database lives: opening one (creating it when
/// missing), closing it when another account becomes active, and deleting
/// one. Null is the signed-out database.
abstract interface class DatabaseFiles {
  Future<Database> open(String? userId);
  Future<void> close(Database database);
  Future<void> delete(String userId);
}

/// Relational SQLite database for offline-first transactional finance data.
///
/// Every account signed in on the device has its own file, so switching
/// accounts never mixes their rows or their unsent changes, and switching
/// works offline (docs/07_OFFLINE_SYNC.md). Repositories always go through
/// [db], which is the active account's file.
class AppDatabase {
  AppDatabase({
    Database? database,
    this._files,
    this._userId,
    this._switchSettle = const Duration(milliseconds: 300),
  }) : _db = database;

  static String get databaseName => AppEnv.databaseName;
  static const int databaseVersion = 1;

  /// Database file name of [userId]; null is the signed-out file, which is
  /// also the single file used before accounts had their own.
  static String fileNameFor(String? userId) {
    if (userId == null) return databaseName;
    if (!_safeId.hasMatch(userId)) {
      throw ArgumentError.value(userId, 'userId', 'not a user id');
    }
    return '${p.basenameWithoutExtension(databaseName)}_$userId.db';
  }

  static final RegExp _safeId = RegExp(r'^[0-9a-zA-Z-]{1,64}$');

  /// Between closing one account's file and opening the next, so a write
  /// that was already under way fails on the closed file instead of landing
  /// in the next account's (repository writes are several statements).
  final Duration _switchSettle;

  /// Null when the database was given directly (tests): there is then one
  /// shared database and per-account operations fall back to clearing it.
  final DatabaseFiles? _files;
  String? _userId;
  Database? _db;

  /// The account whose file is open; null for the signed-out file.
  String? get userId => _userId;

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

  /// Opens [userId]'s database (the signed-out one for null) from the app's
  /// database directory.
  static Future<AppDatabase> open({String? userId}) async {
    initializePlatform();
    final AppDatabase database = AppDatabase(files: _DeviceFiles());
    await database.openFor(userId);
    return database;
  }

  /// Creates in-memory database instance for testing.
  static Future<AppDatabase> inMemory() async {
    sqfliteFfiInit();
    final Database database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: _onCreate,
      ),
    );
    return AppDatabase(database: database);
  }

  /// In-memory databases that behave like per-account files, for tests of
  /// account switching: each account keeps its rows while another is active.
  static Future<AppDatabase> inMemoryFiles({String? userId}) async {
    sqfliteFfiInit();
    final AppDatabase database = AppDatabase(
      files: _MemoryFiles(),
      switchSettle: Duration.zero,
    );
    await database.openFor(userId);
    return database;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
    await _seedSystemCategories(db);
  }

  /// Makes [userId]'s file the open database (null: the signed-out one),
  /// closing the previous file. The caller makes sure nothing else uses the
  /// database meanwhile (AccountSwitchController pauses sync and removes the
  /// screens first).
  Future<void> openFor(String? userId) async {
    final DatabaseFiles? files = _files;
    if (files == null) {
      _userId = userId;
      return;
    }
    if (isOpen && _userId == userId) return;
    final Database? previous = _db;
    _db = null;
    if (previous != null) {
      await files.close(previous);
      await Future<void>.delayed(_switchSettle);
    }
    _db = await files.open(userId);
    _userId = userId;
  }

  /// Removes everything stored on this device for [userId] (sign-out). Their
  /// file must not be the open one. A single shared database is cleared
  /// instead, and only while no account is active in it: another account's
  /// leftovers there are wiped by SyncEngine.claimLocalData before it syncs.
  Future<void> removeUser(String userId) async {
    final DatabaseFiles? files = _files;
    if (files == null) {
      if (_userId == null) await clearAllUserData();
      return;
    }
    if (isOpen && _userId == userId) {
      throw StateError('The database of the active account is still open.');
    }
    await files.delete(userId);
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
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

  Future<List<SyncQueueItem>> getPendingQueue({
    int limit = 50,
    int afterId = 0,
  }) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'sync_queue',
      where: "status IN ('pending', 'failed') AND id > ?",
      whereArgs: <Object>[afterId],
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

  /// Metadata key holding the user whose data the local tables hold.
  static const String localOwnerKey = 'local_owner';

  /// Wipes all non-system data, the upload queue and the pull cursors, in one
  /// transaction. Used when the signed-in user changes: the local tables are
  /// not scoped by user, so another account must never read or upload them.
  Future<void> clearAllUserData() => db.transaction((Transaction txn) async {
    for (final String table in <String>[
      'accounts',
      'transactions',
      'contacts',
      'contact_transactions',
      'budgets',
      'recurring_transactions',
      'reminders',
      'user_settings',
      'profiles',
      'sync_queue',
    ]) {
      await txn.delete(table);
    }
    await txn.delete('categories', where: 'is_system = 0');
    // Without its rows the next sign-in must pull everything again.
    await txn.delete('sync_metadata', where: "key LIKE 'cursor_%'");
  });
}

/// One SQLite file per account in the app's database directory.
class _DeviceFiles implements DatabaseFiles {
  @override
  Future<Database> open(String? userId) async {
    final String directory = await getDatabasesPath();
    final String path = p.join(directory, AppDatabase.fileNameFor(userId));
    if (userId != null && !await databaseExists(path)) {
      await _adoptSharedFile(directory, userId, path);
    }
    return openDatabase(
      path,
      version: AppDatabase.databaseVersion,
      onCreate: AppDatabase._onCreate,
    );
  }

  @override
  Future<void> close(Database database) => database.close();

  @override
  Future<void> delete(String userId) async {
    final String path = p.join(
      await getDatabasesPath(),
      AppDatabase.fileNameFor(userId),
    );
    await deleteDatabase(path);
  }

  /// Before accounts had their own files, everything lived in the shared
  /// file. If it holds [userId]'s data (or nobody's yet), it becomes their
  /// file, so an update keeps unsent changes instead of downloading again.
  Future<void> _adoptSharedFile(
    String directory,
    String userId,
    String path,
  ) async {
    final String shared = p.join(directory, AppDatabase.fileNameFor(null));
    if (!await databaseExists(shared)) return;
    try {
      final Database database = await openDatabase(shared);
      String? owner;
      try {
        final List<Map<String, Object?>> rows = await database.query(
          'sync_metadata',
          columns: <String>['value'],
          where: 'key = ?',
          whereArgs: <Object>[AppDatabase.localOwnerKey],
          limit: 1,
        );
        owner = rows.isEmpty ? null : rows.first['value'] as String?;
      } finally {
        await database.close();
      }
      if (owner != null && owner != userId) return;
      for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
        final File file = File('$shared$suffix');
        if (file.existsSync()) await file.rename('$path$suffix');
      }
    } on Object catch (error) {
      // The account starts from an empty file and downloads its data.
      developer.log(
        'Shared database not adopted: ${error.runtimeType}',
        name: 'database',
      );
    }
  }
}

/// In-memory stand-in for [_DeviceFiles]: databases stay open while another
/// account is active, as files would stay on disk.
class _MemoryFiles implements DatabaseFiles {
  final Map<String?, Database> _open = <String?, Database>{};

  @override
  Future<Database> open(String? userId) async =>
      _open[userId] ??= await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: AppDatabase.databaseVersion,
          onCreate: AppDatabase._onCreate,
          singleInstance: false,
        ),
      );

  @override
  Future<void> close(Database database) async {}

  @override
  Future<void> delete(String userId) async {
    await _open.remove(userId)?.close();
  }
}
