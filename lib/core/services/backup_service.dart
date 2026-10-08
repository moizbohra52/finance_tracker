import 'dart:convert';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
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
    'user_settings',
    'profiles',
  ];

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
        } else if (table == 'categories') {
          where = 'user_id = ? OR is_system = 1';
          whereArgs = <Object>[userId];
        } else if (table == 'user_settings') {
          where = 'user_id = ?';
          whereArgs = <Object>[userId];
        } else {
          where = 'user_id = ?';
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
        'The selected backup file is empty.',
      );
    }

    final dynamic parsed;
    try {
      parsed = jsonDecode(jsonString);
    } catch (e) {
      return BackupValidationResult.invalid(
        'Invalid file format. The file is not a valid JSON document.',
      );
    }

    if (parsed is! Map<String, dynamic>) {
      return BackupValidationResult.invalid(
        'Invalid backup structure. Root element must be a JSON object.',
      );
    }

    // Check version
    final dynamic version = parsed['version'];
    if (version == null || version is! int) {
      return BackupValidationResult.invalid(
        'Invalid backup file: missing or invalid "version" field.',
      );
    }
    if (version > currentBackupVersion) {
      return BackupValidationResult.invalid(
        'Backup version $version is newer than supported version $currentBackupVersion. Please update the app.',
      );
    }

    // Check data section
    final dynamic rawData = parsed['data'];
    if (rawData == null || rawData is! Map<String, dynamic>) {
      return BackupValidationResult.invalid(
        'Invalid backup file: "data" section is missing or invalid.',
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
        'This backup does not contain any records to restore.',
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

  /// Restores data from validated backup into SQLite database.
  /// If [replaceExisting] is true, deletes previous user data before inserting.
  /// If [replaceExisting] is false, merges records using [ConflictAlgorithm.replace] on primary keys.
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
          for (final String table in supportedTables) {
            if (table == 'categories') {
              // Preserve system categories
              if (userId != null) {
                await txn.delete(
                  table,
                  where: 'user_id = ?',
                  whereArgs: <Object>[userId],
                );
              } else {
                await txn.delete(table, where: 'is_system = 0');
              }
            } else if (table == 'profiles') {
              if (userId != null) {
                await txn.delete(
                  table,
                  where: 'id = ?',
                  whereArgs: <Object>[userId],
                );
              } else {
                await txn.delete(table);
              }
            } else {
              if (userId != null) {
                await txn.delete(
                  table,
                  where: 'user_id = ?',
                  whereArgs: <Object>[userId],
                );
              } else {
                await txn.delete(table);
              }
            }
          }
        }

        // Step 2: Insert rows table by table in dependency order
        // Order: categories -> accounts -> contacts -> transactions -> contact_transactions -> budgets -> recurring -> reminders -> settings -> profiles
        const List<String> insertOrder = <String>[
          'categories',
          'accounts',
          'contacts',
          'transactions',
          'contact_transactions',
          'budgets',
          'recurring_transactions',
          'reminders',
          'user_settings',
          'profiles',
        ];

        for (final String table in insertOrder) {
          final List<Map<String, dynamic>>? rows = data[table];
          if (rows == null || rows.isEmpty) {
            restoredCounts[table] = 0;
            continue;
          }

          int insertedForTable = 0;
          for (final Map<String, dynamic> row in rows) {
            // Re-insert or replace
            await txn.insert(
              table,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
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
      return RestoreResult.failed('Failed to restore backup: $e');
    }
  }
}
