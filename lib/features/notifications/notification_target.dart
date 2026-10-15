import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/routes/app_routes.dart';

/// Where tapping a notification goes: a route, its argument, and the account
/// the notification belongs to.
class NotificationTarget {
  const NotificationTarget(this.route, [this.argument, this.userId]);

  final String route;

  /// The id the route expects as `Get.arguments`, when it takes one.
  final String? argument;

  /// The signed-in account the notification is for. Null when unknown
  /// (notifications scheduled before accounts were tagged, pushes without a
  /// `user_id`): those open in the active account.
  final String? userId;

  NotificationTarget forUser(String? userId) =>
      NotificationTarget(route, argument, userId);

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget &&
      other.route == route &&
      other.argument == argument &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(route, argument, userId);

  @override
  String toString() => 'NotificationTarget($route, $argument, $userId)';

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  /// Supabase user ids are UUIDs; anything id-like is accepted because an
  /// owner is only ever compared with the accounts saved on the device.
  static final RegExp _userId = RegExp(r'^[0-9A-Za-z-]{1,64}$');

  static const String _ownerSeparator = '|';

  /// `type:id`, the payload local notifications carry, prefixed with
  /// `userId|` when the owning account is known.
  static String payload(String type, String? referenceId, {String? userId}) {
    final String target = referenceId == null ? type : '$type:$referenceId';
    return withOwner(target, userId);
  }

  /// [payload] tagged with the account it belongs to. An already tagged
  /// payload keeps its owner.
  static String withOwner(String payload, String? userId) =>
      userId == null || ownerOf(payload) != null
      ? payload
      : '$userId$_ownerSeparator$payload';

  /// The account a payload belongs to, or null for an untagged one.
  static String? ownerOf(String? payload) {
    if (payload == null) return null;
    final int split = payload.indexOf(_ownerSeparator);
    if (split <= 0) return null;
    final String owner = payload.substring(0, split);
    return _userId.hasMatch(owner) ? owner : null;
  }

  /// Resolves a local-notification payload, or null when there is none.
  static NotificationTarget? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final String? owner = ownerOf(payload);
    final String target = owner == null
        ? payload
        : payload.substring(owner.length + _ownerSeparator.length);
    if (target.isEmpty) return null;
    final int split = target.indexOf(':');
    final NotificationTarget resolved = split < 0
        ? resolve(target, null)
        : resolve(target.substring(0, split), target.substring(split + 1));
    return resolved.forUser(owner);
  }

  /// Resolves an FCM data message. The server sends `type`, `reference_id`
  /// and `user_id` (the account it is for).
  static NotificationTarget? fromData(Map<String, dynamic> data) {
    final Object? type = data['type'];
    if (type is! String || type.isEmpty) return null;
    final Object? id = data['reference_id'];
    return resolve(
      type,
      id is String ? id : null,
    ).forUser(userIdFromData(data));
  }

  /// The `user_id` of an FCM data message, when it is a valid id.
  static String? userIdFromData(Map<String, dynamic> data) {
    final Object? userId = data['user_id'];
    return userId is String && _userId.hasMatch(userId) ? userId : null;
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
