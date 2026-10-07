import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Row payloads for Supabase writes. The server owns identity and timestamps:
/// `user_id` is taken from the session (RLS rejects anything else) and
/// `created_at`/`updated_at` come from column defaults and triggers.
Map<String, dynamic> insertPayload(
  SupabaseClient client,
  Map<String, dynamic> json,
) {
  final String? userId = client.auth.currentUser?.id;
  if (userId == null) throw AuthFailure.sessionExpired;
  return <String, dynamic>{...json, 'user_id': userId}
    ..remove('created_at')
    ..remove('updated_at')
    ..remove('deleted_at');
}

/// Edits never change ownership, creation time or the delete tombstone.
Map<String, dynamic> updatePayload(Map<String, dynamic> json) =>
    <String, dynamic>{...json}
      ..remove('user_id')
      ..remove('created_at')
      ..remove('updated_at')
      ..remove('deleted_at');

/// Soft-delete patch: tombstones sync to other devices (docs/07_OFFLINE_SYNC.md).
Map<String, dynamic> tombstone() => <String, dynamic>{
  'deleted_at': DateTime.now().toUtc().toIso8601String(),
};
