import 'package:finance_tracker/core/services/notification_permission_state.dart';
import 'package:finance_tracker/features/notifications/notification_target.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String id = 'a1b2c3d4-0000-4000-8000-000000000001';

  group('deep-link target resolution', () {
    test('a reminder payload opens that reminder', () {
      expect(
        NotificationTarget.fromPayload('reminder:$id'),
        const NotificationTarget(AppRoutes.reminderDetail, id),
      );
    });

    test('budget, recurring, contact and transaction notifications', () {
      expect(
        NotificationTarget.fromPayload('budget_alert:$id'),
        const NotificationTarget(AppRoutes.budgets),
      );
      expect(
        NotificationTarget.fromPayload('recurring:$id'),
        const NotificationTarget(AppRoutes.recurring),
      );
      expect(
        NotificationTarget.fromPayload('contact:$id'),
        const NotificationTarget(AppRoutes.contactDetail, id),
      );
      expect(
        NotificationTarget.fromPayload('transaction:$id'),
        const NotificationTarget(AppRoutes.transactionDetail, id),
      );
    });

    test('payload() and fromPayload() round-trip', () {
      expect(
        NotificationTarget.fromPayload(
          NotificationTarget.payload('reminder', id),
        ),
        const NotificationTarget(AppRoutes.reminderDetail, id),
      );
    });

    test('no payload means no target', () {
      expect(NotificationTarget.fromPayload(null), isNull);
      expect(NotificationTarget.fromPayload(''), isNull);
    });

    test('an unknown type falls back to the notification center', () {
      expect(
        NotificationTarget.fromPayload('something_new:$id'),
        const NotificationTarget(AppRoutes.notifications),
      );
      expect(
        NotificationTarget.fromPayload('whatever'),
        const NotificationTarget(AppRoutes.notifications),
      );
    });

    test('a missing or malformed id never reaches a route argument', () {
      // Push payloads come from outside the app, so ids are validated.
      for (final String bad in <String>[
        'reminder',
        'reminder:',
        'reminder:not-a-uuid',
        'reminder:../../etc',
        'contact:1; drop table',
      ]) {
        expect(
          NotificationTarget.fromPayload(bad),
          const NotificationTarget(AppRoutes.notifications),
          reason: bad,
        );
      }
    });

    test('push data uses type and reference_id', () {
      expect(
        NotificationTarget.fromData(<String, dynamic>{
          'type': 'reminder',
          'reference_id': id,
        }),
        const NotificationTarget(AppRoutes.reminderDetail, id),
      );
      expect(
        NotificationTarget.fromData(<String, dynamic>{'type': 'budget_alert'}),
        const NotificationTarget(AppRoutes.budgets),
      );
    });

    test('push data without a type has no target', () {
      expect(NotificationTarget.fromData(<String, dynamic>{}), isNull);
      expect(
        NotificationTarget.fromData(<String, dynamic>{'type': 42}),
        isNull,
      );
    });
  });

  group('permission state handling', () {
    NotificationPermissionState resolve({
      bool supported = true,
      required bool granted,
      required bool asked,
    }) => NotificationPermissionState.resolve(
      supported: supported,
      granted: granted,
      alreadyAsked: asked,
    );

    test('granted wins whatever happened before', () {
      expect(
        resolve(granted: true, asked: false),
        NotificationPermissionState.granted,
      );
      expect(
        resolve(granted: true, asked: true),
        NotificationPermissionState.granted,
      );
    });

    test('never asked and not granted can still be prompted', () {
      final NotificationPermissionState s = resolve(
        granted: false,
        asked: false,
      );
      expect(s, NotificationPermissionState.denied);
      expect(s.canPrompt, isTrue);
      expect(s.needsSettings, isFalse);
    });

    test('refused after asking is blocked: only settings can help', () {
      final NotificationPermissionState s = resolve(
        granted: false,
        asked: true,
      );
      expect(s, NotificationPermissionState.blocked);
      expect(s.canPrompt, isFalse);
      expect(s.needsSettings, isTrue);
    });

    test('an unsupported platform reports unsupported', () {
      expect(
        resolve(supported: false, granted: true, asked: false),
        NotificationPermissionState.unsupported,
      );
    });
  });
}
