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
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:finance_tracker/features/notifications/widgets/notification_permission_banner.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:finance_tracker/features/reminders/widgets/reminder_visuals.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void openAddReminder() => Get.toNamed<void>(
  AppRoutes.reminderForm,
  arguments: const ReminderFormArgs(),
);

class ReminderListView extends GetView<ReminderController> {
  const ReminderListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Reminders'),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const AppContent(
              child: SkeletonList(count: 4, type: SkeletonType.generic),
            );
          }
          final String? error = controller.error.value;
          if (error != null && controller.reminders.isEmpty) {
            return LoadFailureView(message: error, onRetry: controller.load);
          }
          if (controller.reminders.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No reminders',
              message:
                  'Never miss a payment. Add a reminder for a bill, money '
                  'you are owed, or anything else.',
              actionLabel: 'Add reminder',
              onAction: openAddReminder,
            );
          }
          return AppContent(
            child: RefreshIndicator(
              onRefresh: controller.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 88),
                children: <Widget>[
                  const NotificationPermissionBanner(),
                  SubmitErrorMessage(controller.action),
                  for (final ReminderSection section in controller.sections())
                    ..._section(context, section),
                ],
              ),
            ),
          );
        }),
      ),
      floatingActionButton: const FloatingActionButton.extended(
        onPressed: openAddReminder,
        icon: Icon(Icons.add),
        label: Text('Add reminder'),
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    ReminderSection section,
  ) => <Widget>[
    Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
      child: Text(section.title, style: Theme.of(context).textTheme.titleSmall),
    ),
    for (final Reminder reminder in section.reminders)
      _ReminderTile(reminder: reminder),
  ];
}

class _ReminderTile extends GetView<ReminderController> {
  const _ReminderTile({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ReminderStatus status = ReminderCalculator.status(
      reminder,
      DateTime.now(),
    );
    final bool done = status == ReminderStatus.completed;
    final DateTime shown = status == ReminderStatus.snoozed
        ? reminder.snoozedUntil!
        : reminder.remindAt;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: EdgeInsets.zero,
      child: AppListTile(
        onTap: () =>
            Get.toNamed<void>(AppRoutes.reminderDetail, arguments: reminder.id),
        leading: IconBadge(icon: reminderIcon(reminder.type)),
        title: reminder.title,
        titleStyle: TextStyle(
          decoration: done ? TextDecoration.lineThrough : null,
        ),
        subtitle:
            '${AppFormatters.dateTime(shown)}'
            '${reminder.repeat.repeats ? ' · ${reminder.repeat.label}' : ''}',
        subtitleMaxLines: 2,
        caption: StatusPill(
          label: status.label,
          color: reminderStatusColor(colors, status),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (reminder.amount != null)
              MoneyText(
                reminder.amount!,
                flow: switch (reminder.type) {
                  ReminderType.receivable => MoneyFlow.inflow,
                  ReminderType.payable => MoneyFlow.outflow,
                  _ => MoneyFlow.neutral,
                },
              ),
            if (!done)
              Semantics(
                label: reminder.notificationEnabled
                    ? 'Turn notification off'
                    : 'Turn notification on',
                child: Switch(
                  value: reminder.notificationEnabled,
                  onChanged: (bool v) =>
                      controller.setNotificationEnabled(reminder, v),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
