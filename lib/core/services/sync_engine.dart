import 'dart:async';
import 'dart:developer' as developer;

import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SyncState {
  /// All local changes have been uploaded and data is in sync.
  synced,

  /// Actively synchronizing with remote.
  syncing,

  /// Network transport is offline.
  offline,

  /// Changes are queued waiting for network or sync trigger.
  waiting,

  /// Last sync attempt encountered an error.
  error,
}

/// Coordinates offline-first synchronization between local SQLite and Supabase.
class SyncEngine extends GetxService {
  SyncEngine({
    required AppDatabase database,
    SupabaseClient? client,
    ConnectivityService? connectivity,
    DataChangeNotifier? notifier,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _client = client,
       // ignore: prefer_initializing_formals
       _connectivity = connectivity,
       // ignore: prefer_initializing_formals
       _notifier = notifier;

  final AppDatabase _db;
  final SupabaseClient? _client;
  final ConnectivityService? _connectivity;
  final DataChangeNotifier? _notifier;

  final Rx<SyncState> state = SyncState.synced.obs;
  final RxInt pendingCount = 0.obs;
  final RxInt failedCount = 0.obs;
  final Rxn<DateTime> lastSyncedAt = Rxn<DateTime>();
  final RxnString lastError = RxnString();

  bool _isSyncing = false;
  bool _pendingSyncRequest = false;
  StreamSubscription<NetworkStatus>? _networkSubscription;

  /// Maximum retry attempts before a queue item stays marked as failed.
  static const int maxRetries = 5;

  /// Window to overlap when querying server delta changes (to protect against
  /// transaction start-time clock skew as specified in docs/07_OFFLINE_SYNC.md).
  static const Duration pullOverlap = Duration(seconds: 15);

  @override
  void onInit() {
    super.onInit();
    unawaited(refreshQueueStats());

    // Listen to network changes: trigger auto-sync when online.
    if (_connectivity != null) {
      _networkSubscription = _connectivity.status.listen((
        NetworkStatus network,
      ) {
        if (network == NetworkStatus.online) {
          unawaited(syncAll());
        } else if (network == NetworkStatus.offline) {
          state.value = SyncState.offline;
        }
      });
    }
  }

  @override
  void onClose() {
    _networkSubscription?.cancel();
    super.onClose();
  }

  /// Refreshes the reactive pending queue count.
  Future<void> refreshQueueStats() async {
    try {
      final int pending = await _db.getPendingQueueCount();
      pendingCount.value = pending;

      final List<Map<String, dynamic>> failedRows = await _db.db.rawQuery(
        "SELECT COUNT(*) as cnt FROM sync_queue WHERE status = 'failed'",
      );
      failedCount.value = failedRows.isNotEmpty
          ? ((failedRows.first['cnt'] as num?)?.toInt() ?? 0)
          : 0;

      if (_connectivity != null && _connectivity.isOffline) {
        state.value = SyncState.offline;
      } else if (pending > 0 && state.value != SyncState.syncing) {
        state.value = failedCount.value > 0
            ? SyncState.error
            : SyncState.waiting;
      } else if (pending == 0 && state.value != SyncState.syncing) {
        state.value = SyncState.synced;
      }
    } on Object catch (e) {
      developer.log('Error refreshing sync queue stats: $e', name: 'sync');
    }
  }

  /// Notifies the engine that a new item was enqueued. Triggers sync if online.
  void notifyNewQueueItem() {
    unawaited(refreshQueueStats());
    if (_connectivity == null || !_connectivity.isOffline) {
      unawaited(syncAll());
    }
  }

  /// Performs full two-way synchronization: uploads pending queue then downloads delta.
  Future<void> syncAll() async {
    if (_isSyncing) {
      _pendingSyncRequest = true;
      return;
    }

    if (_connectivity != null && _connectivity.isOffline) {
      state.value = SyncState.offline;
      return;
    }

    if (_client == null || _client.auth.currentUser == null) {
      // No active remote session.
      await refreshQueueStats();
      return;
    }

    _isSyncing = true;
    state.value = SyncState.syncing;
    lastError.value = null;

    try {
      // 0. Never upload or show another account's local rows as this one's.
      await claimLocalData(_client.auth.currentUser!.id);

      // 1. Upload local changes
      await uploadPending();

      // 2. Download remote changes
      await downloadDelta();

      lastSyncedAt.value = DateTime.now();
      state.value = SyncState.synced;

      // Clean up successfully synced queue records
      await _db.clearSyncedQueueItems();
      await refreshQueueStats();

      _notifier?.markChanged();
    } on Object catch (error) {
      developer.log('Sync failed: $error', name: 'sync');
      lastError.value = _safeErrorMessage(error);
      state.value = SyncState.error;
      await refreshQueueStats();
    } finally {
      _isSyncing = false;
      if (_pendingSyncRequest) {
        _pendingSyncRequest = false;
        unawaited(syncAll());
      }
    }
  }

  /// The local tables are not scoped by user, and an upload takes its
  /// `user_id` from the session. Sign-out clears them (resetUserScope), but
  /// that can be missed, e.g. when the session ends while the app is closed.
  /// So before syncing for [userId], data left by another account is wiped.
  @visibleForTesting
  Future<void> claimLocalData(String userId) async {
    final String? owner = await _db.getMetadata(AppDatabase.localOwnerKey);
    if (owner == userId) return;
    if (owner != null) {
      await _db.clearAllUserData();
      _notifier?.markChanged();
    }
    await _db.setMetadata(AppDatabase.localOwnerKey, userId);
  }

  /// Uploads all pending queue items in FIFO order.
  Future<void> uploadPending() async {
    final SupabaseClient? client = _client;
    if (client == null || client.auth.currentUser == null) return;

    final List<SyncQueueItem> queue = await _db.getPendingQueue(limit: 100);
    if (queue.isEmpty) return;

    for (final SyncQueueItem item in queue) {
      if (item.id == null) continue;

      // Mark processing
      await _db.updateQueueItemStatus(
        id: item.id!,
        status: SyncItemStatus.processing,
        lastAttempt: DateTime.now(),
      );

      try {
        await _executeUploadOperation(client, item);

        // Success: mark synced in queue and in local table
        await _db.updateQueueItemStatus(
          id: item.id!,
          status: SyncItemStatus.synced,
        );
        await _db.markEntitySynced(item.entity, item.entityId);
      } on Object catch (error) {
        final int nextRetry = item.retryCount + 1;
        final String safeMsg = _safeErrorMessage(error);
        developer.log(
          'Failed syncing item ${item.entity} (${item.entityId}): $safeMsg',
          name: 'sync',
        );

        final SyncItemStatus nextStatus = nextRetry >= maxRetries
            ? SyncItemStatus.failed
            : SyncItemStatus.pending;

        await _db.updateQueueItemStatus(
          id: item.id!,
          status: nextStatus,
          retryCount: nextRetry,
          errorMessage: safeMsg,
        );

        // Stop processing further items if there is a network outage
        if (_isNetworkError(error)) {
          rethrow;
        }
      }
    }
  }

  Future<void> _executeUploadOperation(
    SupabaseClient client,
    SyncQueueItem item,
  ) async {
    final String table = item.entity;
    final Map<String, dynamic> payload = item.payload;

    switch (item.operation) {
      case SyncOperation.create:
        if (table == 'user_settings') {
          final String userId = client.auth.currentUser!.id;
          await client
              .from('user_settings')
              .update(payload)
              .eq('user_id', userId);
        } else if (table == 'profiles') {
          final String userId = client.auth.currentUser!.id;
          await client.from('profiles').update(payload).eq('id', userId);
        } else {
          final bool onlyIfAbsent = payload['__only_if_absent'] == true;
          final Map<String, dynamic> clean = Map<String, dynamic>.from(payload)
            ..remove('__only_if_absent')
            ..remove('sync_status');

          await client
              .from(table)
              .upsert(
                insertPayload(client, clean),
                ignoreDuplicates: onlyIfAbsent,
              );
        }

      case SyncOperation.update:
        if (table == 'user_settings') {
          final String userId = client.auth.currentUser!.id;
          await client
              .from('user_settings')
              .update(payload)
              .eq('user_id', userId);
        } else if (table == 'profiles') {
          final String userId = client.auth.currentUser!.id;
          await client.from('profiles').update(payload).eq('id', userId);
        } else {
          final Map<String, dynamic> clean = Map<String, dynamic>.from(payload)
            ..remove('sync_status');
          await client
              .from(table)
              .update(updatePayload(clean))
              .eq('id', item.entityId);
        }

      case SyncOperation.delete:
        await client.from(table).update(tombstone()).eq('id', item.entityId);
    }
  }

  /// Downloads changed records from Supabase since the last cursor.
  Future<void> downloadDelta() async {
    final SupabaseClient? client = _client;
    if (client == null || client.auth.currentUser == null) return;
    final String userId = client.auth.currentUser!.id;

    final List<String> syncableTables = <String>[
      'accounts',
      'categories',
      'transactions',
      'contacts',
      'contact_transactions',
      'budgets',
      'recurring_transactions',
      'reminders',
    ];

    for (final String table in syncableTables) {
      await _pullTable(client, table, userId);
    }

    // Pull user settings and profile
    await _pullUserSettings(client, userId);
    await _pullProfile(client, userId);
  }

  Future<void> _pullTable(
    SupabaseClient client,
    String table,
    String userId,
  ) async {
    final String metadataKey = 'cursor_${table}_$userId';
    final String? lastCursorStr = await _db.getMetadata(metadataKey);

    DateTime? cursor;
    if (lastCursorStr != null) {
      cursor = DateTime.tryParse(lastCursorStr)?.subtract(pullOverlap);
    }

    PostgrestFilterBuilder<List<Map<String, dynamic>>> query = client
        .from(table)
        .select();

    if (table == 'categories') {
      // System or user's own categories
      query = query.or('user_id.eq.$userId,is_system.eq.true');
    } else {
      query = query.eq('user_id', userId);
    }

    if (cursor != null) {
      query = query.gte('updated_at', cursor.toUtc().toIso8601String());
    }

    final List<Map<String, dynamic>> remoteRows = await query.order(
      'updated_at',
      ascending: true,
    );

    if (remoteRows.isEmpty) return;

    DateTime? maxUpdatedAt;

    for (final Map<String, dynamic> row in remoteRows) {
      final String id = row['id'] as String;
      final String? updatedAtStr = row['updated_at'] as String?;
      if (updatedAtStr != null) {
        final DateTime rowUpdatedAt = DateTime.parse(updatedAtStr);
        if (maxUpdatedAt == null || rowUpdatedAt.isAfter(maxUpdatedAt)) {
          maxUpdatedAt = rowUpdatedAt;
        }
      }

      // Check conflict: does local have un-synced edits for this row?
      final bool hasPending = await _db.hasPendingSyncFor(table, id);
      if (hasPending) {
        _handleConflict(table, id, row);
        continue;
      }

      // Safe to upsert locally
      await _upsertLocalRow(table, row);
    }

    if (maxUpdatedAt != null) {
      await _db.setMetadata(metadataKey, maxUpdatedAt.toIso8601String());
    }
  }

  Future<void> _pullUserSettings(SupabaseClient client, String userId) async {
    try {
      final List<Map<String, dynamic>> rows = await client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (rows.isNotEmpty) {
        final Map<String, dynamic> row = rows.first;
        final bool hasPending = await _db.hasPendingSyncFor(
          'user_settings',
          row['id'] as String? ?? userId,
        );
        if (!hasPending) {
          final Map<String, dynamic> localData = <String, dynamic>{
            'id': row['id'] ?? userId,
            'user_id': userId,
            'date_format': row['date_format'],
            'number_format': row['number_format'],
            'first_day_of_week': row['first_day_of_week'],
            'language_code': row['language_code'],
            'default_account_id': row['default_account_id'],
            'notifications_enabled':
                (row['notifications_enabled'] as bool? ?? true) ? 1 : 0,
            'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
            'updated_at': row['updated_at'] ?? DateTime.now().toIso8601String(),
            'sync_status': 'synced',
          };
          await _db.db.insert(
            'user_settings',
            localData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    } on Object catch (e) {
      developer.log('Error pulling user_settings: $e', name: 'sync');
    }
  }

  Future<void> _pullProfile(SupabaseClient client, String userId) async {
    try {
      final List<Map<String, dynamic>> rows = await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .limit(1);

      if (rows.isNotEmpty) {
        final Map<String, dynamic> row = rows.first;
        final Map<String, dynamic> localData = <String, dynamic>{
          'id': userId,
          'full_name': row['full_name'],
          'mobile': row['mobile'],
          'avatar_url': row['avatar_url'],
          'currency_code': row['currency_code'] ?? 'INR',
          'timezone': row['timezone'],
          'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': row['updated_at'] ?? DateTime.now().toIso8601String(),
          'sync_status': 'synced',
        };
        await _db.db.insert(
          'profiles',
          localData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } on Object catch (e) {
      developer.log('Error pulling profile: $e', name: 'sync');
    }
  }

  /// Conflict handling strategy:
  /// - Financial transactions are immutable; local un-synced edits/creates take priority.
  /// - For metadata (accounts, contacts, etc.), logs conflict safely.
  void _handleConflict(
    String table,
    String id,
    Map<String, dynamic> remoteRow,
  ) {
    developer.log(
      'Sync conflict detected for $table (id: $id). Preserving pending local edit.',
      name: 'sync',
    );
  }

  Future<void> _upsertLocalRow(String table, Map<String, dynamic> row) async {
    final Map<String, dynamic> clean = Map<String, dynamic>.from(row);

    // Convert booleans to 1/0 for SQLite
    clean.forEach((String key, dynamic value) {
      if (value is bool) {
        clean[key] = value ? 1 : 0;
      } else if (value is num &&
          (key == 'amount' || key == 'opening_balance')) {
        clean[key] = value.toString();
      }
    });

    clean['sync_status'] = 'synced';

    await _db.db.insert(
      table,
      clean,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retries all failed queue items.
  Future<void> retryFailed() async {
    await _db.db.update('sync_queue', <String, dynamic>{
      'status': SyncItemStatus.pending.name,
      'retry_count': 0,
      'error_message': null,
    }, where: "status = 'failed'");
    await refreshQueueStats();
    await syncAll();
  }

  /// Retrieves list of pending items for UI inspection.
  Future<List<SyncQueueItem>> getPendingItems() async {
    return await _db.getPendingQueue(limit: 100);
  }

  bool _isNetworkError(Object error) {
    final String s = error.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('handshakeexception') ||
        s.contains('timeout') ||
        s.contains('network') ||
        s.contains('connection refused');
  }

  String _safeErrorMessage(Object error) {
    final String s = error.toString();
    if (_isNetworkError(error)) {
      return 'Network connection unavailable. Changes will sync when reconnected.';
    }
    // Strip sensitive information or long stack traces
    if (s.length > 120) {
      return s.substring(0, 120);
    }
    return s;
  }
}
