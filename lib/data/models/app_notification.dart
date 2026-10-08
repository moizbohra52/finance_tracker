import 'package:finance_tracker/domain/entities/app_notification.dart';

/// Row mapping for public.notifications.
abstract final class AppNotificationModel {
  static AppNotification fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    body: json['body'] as String?,
    referenceId: json['reference_id'] as String?,
    readAt: json['read_at'] == null
        ? null
        : DateTime.parse(json['read_at'] as String).toLocal(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
}
