import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/features/notifications/controllers/notification_center_controller.dart';
import 'package:finance_tracker/features/notifications/widgets/notification_permission_banner.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NotificationCenterView extends GetView<NotificationCenterController> {
  const NotificationCenterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: 'Notifications'.tr,
        actions: <Widget>[
          Obx(
            () => IconButton(
              tooltip: 'Mark all as read'.tr,
              icon: const Icon(Icons.done_all_rounded),
              onPressed: controller.unread.value == 0
                  ? null
                  : controller.markAllRead,
            ),
          ),
          IconButton(
            tooltip: 'Notification settings'.tr,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Get.toNamed<void>(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const AppContent(
              child: SkeletonList(count: 5, type: SkeletonType.generic),
            );
          }
          final String? error = controller.error.value;
          if (error != null && controller.items.isEmpty) {
            return LoadFailureView(message: error, onRetry: controller.load);
          }
          if (controller.items.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'You are all caught up'.tr,
              message:
                  'Budget alerts, reminders and recurring transactions show up here.'
                      .tr,
            );
          }
          return AppContent(
            child: RefreshIndicator(
              onRefresh: controller.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  const NotificationPermissionBanner(),
                  SubmitErrorMessage(controller.action),
                  for (final AppNotification n in controller.items)
                    _NotificationTile(notification: n),
                  if (controller.hasMore.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Center(
                        child: TextButton(
                          onPressed: controller.isLoadingMore.value
                              ? null
                              : controller.loadMore,
                          child: Text(
                            controller.isLoadingMore.value
                                ? 'Loading…'.tr
                                : 'Load more'.tr,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

IconData _typeIcon(String type) => switch (type) {
  NotificationType.reminder => Icons.alarm_rounded,
  NotificationType.budgetAlert => Icons.savings_outlined,
  NotificationType.recurring => Icons.event_repeat_outlined,
  _ => Icons.notifications_outlined,
};

class _NotificationTile extends GetView<NotificationCenterController> {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool unread = !notification.isRead;
    final String body = notification.body ?? '';
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: EdgeInsets.zero,
      child: AppListTile(
        onTap: () => controller.open(notification),
        leading: IconBadge(icon: _typeIcon(notification.type)),
        title: notification.title,
        titleStyle: TextStyle(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
        ),
        subtitle:
            '${body.isEmpty ? '' : '$body\n'}'
            '${AppFormatters.dateTime(notification.createdAt)}',
        subtitleMaxLines: 3,
        trailing: unread
            ? Semantics(
                label: 'Unread'.tr,
                child: Icon(Icons.circle, size: 10, color: colors.primary),
              )
            : null,
      ),
    );
  }
}
