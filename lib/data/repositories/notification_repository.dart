import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/models/app_notification.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// public.notifications (the notification center) and public.device_tokens
/// (where FCM pushes are sent).
class NotificationRepository {
  NotificationRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  /// Most unread entries counted for the badge; the UI shows "99+" beyond it.
  static const int unreadCap = 100;

  /// Creates the notification with the caller-chosen [id] unless a row with
  /// that id already exists (read, unread or acted on); an existing row is
  /// never touched. Callers derive [id] from the event, which makes raising
  /// the same event twice a no-op. Returns whether this call created the row,
  /// so only the first raise of an event also shows a device notification.
  Future<bool> raiseOnce({
    required String id,
    required String type,
    required String title,
    required String body,
    required String referenceId,
  }) => guardSupabase(() async {
    // With ignore-duplicates, PostgREST returns only the rows it inserted.
    final List<Map<String, dynamic>> inserted = await _supabaseClient
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
        )
        .select('id');
    return inserted.isNotEmpty;
  });

  /// Newest first. Paged, because the center grows without bound.
  Future<List<AppNotification>> getPage({int limit = 30, int offset = 0}) =>
      guardSupabase(() async {
        final List<Map<String, dynamic>> data = await _supabaseClient
            .from('notifications')
            .select()
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
        return data.map(AppNotificationModel.fromJson).toList();
      });

  /// Number of unread entries, capped at [unreadCap].
  Future<int> unreadCount() => guardSupabase(() async {
    final List<Map<String, dynamic>> data = await _supabaseClient
        .from('notifications')
        .select('id')
        .isFilter('read_at', null)
        .limit(unreadCap);
    return data.length;
  });

  Future<void> markRead(String id) => guardSupabase(() async {
    await _supabaseClient
        .from('notifications')
        .update(<String, dynamic>{
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .isFilter('read_at', null);
  });

  Future<void> markAllRead() => guardSupabase(() async {
    await _supabaseClient
        .from('notifications')
        .update(<String, dynamic>{
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .isFilter('read_at', null);
  });

  /// One row per user and install; a refreshed token overwrites the old one.
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    required String deviceId,
  }) => guardSupabase(() async {
    await _supabaseClient
        .from('device_tokens')
        .upsert(
          insertPayload(_supabaseClient, <String, dynamic>{
            'token': token,
            'platform': platform,
            'device_id': deviceId,
            'active': true,
          }),
          onConflict: 'user_id,device_id',
        );
  });

  /// Stops pushes to this install, e.g. at sign-out.
  Future<void> deactivateDeviceToken(String deviceId) =>
      guardSupabase(() async {
        await _supabaseClient
            .from('device_tokens')
            .update(<String, dynamic>{'active': false})
            .eq('device_id', deviceId);
      });
}
