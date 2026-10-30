import 'dart:convert';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

/// Validation result returned when parsing and validating a backup file.
class BackupValidationResult {
  const BackupValidationResult({
    required this.isValid,
    this.version = 1,
    this.createdAt,
    this.tableCounts = const <String, int>{},
    this.totalRecords = 0,
    this.errorMessage,
    this.data,
  });

  final bool isValid;
  final int version;
  final DateTime? createdAt;
  final Map<String, int> tableCounts;
  final int totalRecords;
  final String? errorMessage;
  final Map<String, List<Map<String, dynamic>>>? data;

  factory BackupValidationResult.invalid(String error) =>
      BackupValidationResult(isValid: false, errorMessage: error);
}

/// Result returned after restoring a backup.
class RestoreResult {
  const RestoreResult({
    required this.success,
    this.restoredCounts = const <String, int>{},
    this.totalRestored = 0,
    this.errorMessage,
  });

  final bool success;
  final Map<String, int> restoredCounts;
  final int totalRestored;
  final String? errorMessage;

  factory RestoreResult.failed(String error) =>
      RestoreResult(success: false, errorMessage: error);
}

/// Service handling JSON backup creation, schema validation, and database restoration.
class BackupService {
  const BackupService();

  static const int currentBackupVersion = 1;

  static const List<String> supportedTables = <String>[
    'accounts',
    'categories',
    'transactions',
    'contacts',
    'contact_transactions',
    'budgets',
    'recurring_transactions',
    'reminders',
    'savings_goals',
    'savings_contributions',
    'split_groups',
    'split_group_members',
    'split_expenses',
    'split_expense_parts',
    'split_settlements',
    'user_settings',
    'profiles',
  ];

  /// Tables of the user's entries. Restored rows are uploaded through the
  /// sync queue, and a clean restore replaces these tables on the server too.
  static const Set<String> uploadTables = <String>{
    'accounts',
    'categories',
    'transactions',
    'contacts',
    'contact_transactions',
    'budgets',
    'recurring_transactions',
    'reminders',
    'savings_goals',
    'savings_contributions',
    'split_groups',
    'split_group_members',
    'split_expenses',
    'split_expense_parts',
    'split_settlements',
  };

  /// Columns of the signed-in user's settings and profile rows that a restore
  /// applies. The server only lets the app update these two rows, never insert
  /// or delete them. The avatar is left as it is: a backup holds only its
  /// storage path, not the image.
  static const Map<String, List<String>> _preferenceColumns =
      <String, List<String>>{
        'user_settings': <String>[
          'date_format',
          'number_format',
          'first_day_of_week',
          'language_code',
          'default_account_id',
          'upi_id',
        ],
        'profiles': <String>[
          'full_name',
          'mobile',
          'currency_code',
          'timezone',
        ],
      };

  /// Preference columns the server keeps NOT NULL. A backup without a value
  /// keeps the current one instead of queuing an update that always fails.
  static const Set<String> _requiredPreferenceColumns = <String>{
    'first_day_of_week',
    'language_code',
    'currency_code',
  };

  Future<void> _enqueue(
    Transaction txn,
    SyncOperation operation,
    String table,
    String entityId,
    Map<String, dynamic> payload,
  ) => txn.insert(
    'sync_queue',
    SyncQueueItem(
      operation: operation,
      entity: table,
      entityId: entityId,
      payload: payload,
      createdAt: DateTime.now(),
    ).toRow(),
  );

  /// Writes one entry and queues it as an upsert on its id, so a retry never
  /// duplicates. `__restore` makes the upload send the backup's deleted_at
  /// too: an entry deleted after the backup was taken comes back, and one
  /// deleted in the backup is deleted on the server.
  Future<void> _restoreEntry(
    Transaction txn,
    String table,
    Map<String, dynamic> backupRow,
    String? userId,
  ) async {
    final bool system =
        backupRow['is_system'] == 1 || backupRow['is_system'] == true;
    if (!uploadTables.contains(table) || system) {
      // System categories belong to the server and are never uploaded.
      await txn.insert(
        table,
        backupRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    final Map<String, dynamic> row = <String, dynamic>{
      ...backupRow,
      'user_id': ?userId,
      'sync_status': 'pending',
    };
    await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    await _enqueue(
      txn,
      SyncOperation.create,
      table,
      row['id'] as String,
      <String, dynamic>{...row, '__restore': true},
    );
  }

  /// Applies the backup's values to the signed-in user's settings or profile
  /// row and queues the same values as an update.
  Future<void> _restorePreferences(
    Transaction txn,
    String table,
    Map<String, dynamic> backupRow,
    String userId,
  ) async {
    final Map<String, dynamic> values = <String, dynamic>{
      for (final String column in _preferenceColumns[table]!)
        if (backupRow.containsKey(column) &&
            (backupRow[column] != null ||
                !_requiredPreferenceColumns.contains(column)))
          column: backupRow[column],
    };
    if (values.isEmpty) return;

    final String key = table == 'profiles' ? 'id' : 'user_id';
    final int updated = await txn.update(
      table,
      <String, dynamic>{...values, 'sync_status': 'pending'},
      where: '$key = ?',
      whereArgs: <Object>[userId],
    );
    if (updated == 0) {
      await txn.insert(table, <String, dynamic>{
        'id': userId,
        if (table == 'user_settings') 'user_id': userId,
        ...values,
        'sync_status': 'pending',
      });
    }
    await _enqueue(txn, SyncOperation.update, table, userId, values);
  }

  /// Creates a complete JSON backup of the user's data from SQLite.
  /// Never exports passwords, tokens, or private secrets.
  Future<Map<String, dynamic>> createBackup(
    AppDatabase database, {
    String? userId,
  }) async {
    final Map<String, List<Map<String, dynamic>>> tablesData =
        <String, List<Map<String, dynamic>>>{};
    final Map<String, int> counts = <String, int>{};
    int total = 0;

    for (final String table in supportedTables) {
      String? where;
      List<Object>? whereArgs;

      if (userId != null) {
        if (table == 'profiles') {
          where = 'id = ?';
          whereArgs = <Object>[userId];
        } else if (table == 'user_settings') {
          where = 'user_id = ?';
          whereArgs = <Object>[userId];
        } else {
          // An entry saved on this device keeps an empty user_id until its
          // first sync comes back, and it is this user's too. Null also
          // covers the system categories.
          where = "user_id = ? OR user_id IS NULL OR user_id = ''";
          whereArgs = <Object>[userId];
        }
      }

      final List<Map<String, dynamic>> rows = await database.db.query(
        table,
        where: where,
        whereArgs: whereArgs,
      );

      // Sanitize: ensure no sensitive keys are ever included
      final List<Map<String, dynamic>> sanitized = rows.map((r) {
        final Map<String, dynamic> copy = Map<String, dynamic>.from(r);
        copy.remove('password');
        copy.remove('access_token');
        copy.remove('refresh_token');
        copy.remove('token');
        copy.remove('secret');
        return copy;
      }).toList();

      tablesData[table] = sanitized;
      counts[table] = sanitized.length;
      total += sanitized.length;
    }

    final DateTime now = DateTime.now().toUtc();
    return <String, dynamic>{
      'version': currentBackupVersion,
      'app': 'finance_tracker',
      'app_version': AppConstants.appVersion,
      'created_at': now.toIso8601String(),
      'user_id': userId,
      'metadata': <String, dynamic>{'total_records': total, 'tables': counts},
      'data': tablesData,
    };
  }

  /// Validates a raw JSON backup string.
  BackupValidationResult validateBackup(String jsonString) {
    if (jsonString.trim().isEmpty) {
      return BackupValidationResult.invalid(
        'The selected backup file is empty.'.tr,
      );
    }

    final dynamic parsed;
    try {
      parsed = jsonDecode(jsonString);
    } catch (e) {
      return BackupValidationResult.invalid(
        'Invalid file format. The file is not a valid JSON document.'.tr,
      );
    }

    if (parsed is! Map<String, dynamic>) {
      return BackupValidationResult.invalid(
        'Invalid backup structure. Root element must be a JSON object.'.tr,
      );
    }

    // Check version
    final dynamic version = parsed['version'];
    if (version == null || version is! int) {
      return BackupValidationResult.invalid(
        'Invalid backup file: missing or invalid "version" field.'.tr,
      );
    }
    if (version > currentBackupVersion) {
      return BackupValidationResult.invalid(
        'Backup version @version is newer than supported version @supported. Please update the app.'
            .trParams(<String, String>{
              'version': '$version',
              'supported': '$currentBackupVersion',
            }),
      );
    }

    // Check data section
    final dynamic rawData = parsed['data'];
    if (rawData == null || rawData is! Map<String, dynamic>) {
      return BackupValidationResult.invalid(
        'Invalid backup file: "data" section is missing or invalid.'.tr,
      );
    }

    final Map<String, List<Map<String, dynamic>>> validatedData =
        <String, List<Map<String, dynamic>>>{};
    final Map<String, int> tableCounts = <String, int>{};
    int totalCount = 0;

    for (final String table in supportedTables) {
      final dynamic tableRows = rawData[table];
      if (tableRows is List) {
        final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
        for (final dynamic item in tableRows) {
          if (item is Map<String, dynamic>) {
            rows.add(item);
          }
        }
        validatedData[table] = rows;
        tableCounts[table] = rows.length;
        totalCount += rows.length;
      } else {
        validatedData[table] = <Map<String, dynamic>>[];
        tableCounts[table] = 0;
      }
    }

    if (totalCount == 0) {
      return BackupValidationResult.invalid(
        'This backup does not contain any records to restore.'.tr,
      );
    }

    // Parse created timestamp
    DateTime? createdAt;
    if (parsed['created_at'] is String) {
      createdAt = DateTime.tryParse(parsed['created_at'] as String);
    }

    return BackupValidationResult(
      isValid: true,
      version: version,
      createdAt: createdAt,
      tableCounts: tableCounts,
      totalRecords: totalCount,
      data: validatedData,
    );
  }

  /// Restores a validated backup into SQLite and queues it for upload, so the
  /// server ends up matching the restored data (docs/07_OFFLINE_SYNC.md).
  ///
  /// With [replaceExisting] the user's entries on this device are deleted
  /// first, with their unsent changes, and a replace step per table
  /// soft-deletes every server entry the backup does not contain. Otherwise
  /// the backup is merged in, its rows replacing rows with the same id.
  ///
  /// Settings and profile values are applied to the signed-in user's rows in
  /// both modes; the server only lets the app update those rows.
  Future<RestoreResult> restoreBackup(
    AppDatabase database,
    Map<String, List<Map<String, dynamic>>> data, {
    required bool replaceExisting,
    String? userId,
  }) async {
    try {
      final Map<String, int> restoredCounts = <String, int>{};
      int totalRestored = 0;

      await database.db.transaction((Transaction txn) async {
        // Step 1: If clean restore, wipe current user data
        if (replaceExisting) {
          // The device holds one user's data (SyncEngine.claimLocalData), so
          // every entry goes, including ones saved before their first sync,
          // which still have an empty user_id. System categories stay.
          for (final String table in uploadTables) {
            await txn.delete(
              table,
              where: table == 'categories' ? 'is_system = 0' : null,
            );
          }
          await txn.delete(
            'sync_queue',
            where:
                'entity IN (${List<String>.filled(uploadTables.length, '?').join(', ')})',
            whereArgs: uploadTables.toList(),
          );
          // Queued before the restored rows, so the server is cleared first.
          // Entries made after this restore are queued later and kept.
          for (final String table in uploadTables) {
            await _enqueue(
              txn,
              SyncOperation.replace,
              table,
              '*',
              <String, dynamic>{
                'keep_ids': <String>[
                  for (final Map<String, dynamic> row
                      in data[table] ?? const <Map<String, dynamic>>[])
                    row['id'] as String,
                ],
              },
            );
          }
        }

        // Step 2: Insert rows table by table in dependency order
        // Order: categories -> accounts -> contacts -> split groups/members ->
        // split expenses/parts/settlements -> transactions ->
        // contact_transactions -> budgets -> recurring -> reminders ->
        // savings goals -> savings contributions -> settings -> profiles.
        // The split tables come after contacts and before transactions so the
        // server's foreign keys never see a missing parent.
        const List<String> insertOrder = <String>[
          'categories',
          'accounts',
          'contacts',
          'split_groups',
          'split_group_members',
          'split_expenses',
          'split_expense_parts',
          'split_settlements',
          'transactions',
          'contact_transactions',
          'budgets',
          'recurring_transactions',
          'reminders',
          'savings_goals',
          'savings_contributions',
          'user_settings',
          'profiles',
        ];

        for (final String table in insertOrder) {
          final List<Map<String, dynamic>>? rows = data[table];
          if (rows == null || rows.isEmpty) {
            restoredCounts[table] = 0;
            continue;
          }

          // Queued in this order too, so the server gets parents before the
          // rows that reference them.
          int insertedForTable = 0;
          for (final Map<String, dynamic> backupRow in rows) {
            if (userId != null && _preferenceColumns.containsKey(table)) {
              await _restorePreferences(txn, table, backupRow, userId);
            } else {
              await _restoreEntry(txn, table, backupRow, userId);
            }
            insertedForTable++;
          }
          restoredCounts[table] = insertedForTable;
          totalRestored += insertedForTable;
        }
      });

      return RestoreResult(
        success: true,
        restoredCounts: restoredCounts,
        totalRestored: totalRestored,
      );
    } catch (e) {
      return RestoreResult.failed(
        'Failed to restore backup: @error'.trParams(<String, String>{
          'error': '$e',
        }),
      );
    }
  }
}
