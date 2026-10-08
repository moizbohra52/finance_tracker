import 'package:finance_tracker/data/repositories/notification_repository.dart';
import 'package:finance_tracker/features/notifications/controllers/notification_center_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// App-bar bell with the unread count; opens the notification center.
class NotificationBell extends GetView<NotificationCenterController> {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final int count = controller.unread.value;
      final String label = count >= NotificationRepository.unreadCap
          ? '${NotificationRepository.unreadCap - 1}+'
          : '$count';
      return IconButton(
        tooltip: count == 0 ? 'Notifications' : 'Notifications, $count unread',
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(label),
          child: const Icon(Icons.notifications_outlined),
        ),
        onPressed: () => Get.toNamed<void>(AppRoutes.notifications),
      );
    });
  }
}
