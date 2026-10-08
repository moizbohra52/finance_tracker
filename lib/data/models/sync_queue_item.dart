import 'dart:convert';

enum SyncOperation { create, update, delete }

enum SyncItemStatus { pending, processing, failed, synced }

/// A queued synchronization operation to be pushed to Supabase.
class SyncQueueItem {
  const SyncQueueItem({
    this.id,
    required this.operation,
    required this.entity,
    required this.entityId,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastAttempt,
    this.status = SyncItemStatus.pending,
    this.errorMessage,
  });

  factory SyncQueueItem.fromRow(Map<String, dynamic> row) {
    return SyncQueueItem(
      id: row['id'] as int?,
      operation: _parseOperation(row['operation'] as String),
      entity: row['entity'] as String,
      entityId: row['entity_id'] as String,
      payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      createdAt: DateTime.parse(row['created_at'] as String),
      retryCount: (row['retry_count'] as num?)?.toInt() ?? 0,
      lastAttempt: row['last_attempt'] != null
          ? DateTime.parse(row['last_attempt'] as String)
          : null,
      status: _parseStatus(row['status'] as String),
      errorMessage: row['error_message'] as String?,
    );
  }

  final int? id;
  final SyncOperation operation;
  final String entity;
  final String entityId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? lastAttempt;
  final SyncItemStatus status;
  final String? errorMessage;

  Map<String, dynamic> toRow() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'operation': operation.name,
      'entity': entity,
      'entity_id': entityId,
      'payload': jsonEncode(payload),
      'created_at': createdAt.toIso8601String(),
      'retry_count': retryCount,
      'last_attempt': lastAttempt?.toIso8601String(),
      'status': status.name,
      'error_message': errorMessage,
    };
  }

  SyncQueueItem copyWith({
    int? id,
    SyncOperation? operation,
    String? entity,
    String? entityId,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    int? retryCount,
    DateTime? lastAttempt,
    SyncItemStatus? status,
    String? errorMessage,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      operation: operation ?? this.operation,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastAttempt: lastAttempt ?? this.lastAttempt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  static SyncOperation _parseOperation(String op) {
    switch (op) {
      case 'create':
        return SyncOperation.create;
      case 'update':
        return SyncOperation.update;
      case 'delete':
        return SyncOperation.delete;
      default:
        throw ArgumentError('Unknown sync operation: $op');
    }
  }

  static SyncItemStatus _parseStatus(String s) {
    switch (s) {
      case 'pending':
        return SyncItemStatus.pending;
      case 'processing':
        return SyncItemStatus.processing;
      case 'failed':
        return SyncItemStatus.failed;
      case 'synced':
        return SyncItemStatus.synced;
      default:
        throw ArgumentError('Unknown sync status: $s');
    }
  }
}
