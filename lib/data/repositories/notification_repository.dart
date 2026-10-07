import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes rows to public.notifications. Reading, marking read and showing
/// them is Phase 9; budgets only need to raise events idempotently now.
class NotificationRepository {
  NotificationRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  /// Creates the notification with the caller-chosen [id] unless a row with
  /// that id already exists (read, unread or acted on); an existing row is
  /// never touched. Callers derive [id] from the event, which makes raising
  /// the same event twice a no-op.
  Future<void> raiseOnce({
    required String id,
    required String type,
    required String title,
    required String body,
    required String referenceId,
  }) => guardSupabase(() async {
    await _supabaseClient
        .from('notifications')
        .upsert(
          insertPayload(_supabaseClient, <String, dynamic>{
            'id': id,
            'type': type,
            'title': title,
            'body': body,
            'reference_id': referenceId,
          }),
          ignoreDuplicates: true,
        );
  });
}
