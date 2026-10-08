import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/routes/app_routes.dart';

/// Where tapping a notification goes: a route and its argument.
class NotificationTarget {
  const NotificationTarget(this.route, [this.argument]);

  final String route;

  /// The id the route expects as `Get.arguments`, when it takes one.
  final String? argument;

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget &&
      other.route == route &&
      other.argument == argument;

  @override
  int get hashCode => Object.hash(route, argument);

  @override
  String toString() => 'NotificationTarget($route, $argument)';

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  /// `type:id`, the payload local notifications carry.
  static String payload(String type, String? referenceId) =>
      referenceId == null ? type : '$type:$referenceId';

  /// Resolves a local-notification payload, or null when there is none.
  static NotificationTarget? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final int split = payload.indexOf(':');
    return split < 0
        ? resolve(payload, null)
        : resolve(payload.substring(0, split), payload.substring(split + 1));
  }

  /// Resolves an FCM data message. The server sends `type` and `reference_id`.
  static NotificationTarget? fromData(Map<String, dynamic> data) {
    final Object? type = data['type'];
    if (type is! String || type.isEmpty) return null;
    final Object? id = data['reference_id'];
    return resolve(type, id is String ? id : null);
  }

  /// Maps a notification type and the id it refers to onto a screen. Anything
  /// that cannot be opened directly (unknown type, missing or malformed id)
  /// falls back to the notification center, never to a crash or a blank
  /// screen. The id is checked before it is used as a route argument because
  /// push payloads come from outside the app.
  static NotificationTarget resolve(String type, String? referenceId) {
    final String? id = referenceId != null && _uuid.hasMatch(referenceId)
        ? referenceId
        : null;
    switch (type) {
      case NotificationType.reminder:
        if (id != null) return NotificationTarget(AppRoutes.reminderDetail, id);
      case NotificationType.budgetAlert:
      case 'budget':
        return const NotificationTarget(AppRoutes.budgets);
      case NotificationType.recurring:
        return const NotificationTarget(AppRoutes.recurring);
      case 'contact':
      case 'khata':
        if (id != null) return NotificationTarget(AppRoutes.contactDetail, id);
      case 'transaction':
        if (id != null) {
          return NotificationTarget(AppRoutes.transactionDetail, id);
        }
    }
    return const NotificationTarget(AppRoutes.notifications);
  }
}
