import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:finance_tracker/features/contacts/views/send_reminder_sheet.dart';
import 'package:finance_tracker/features/notifications/widgets/notification_permission_banner.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:finance_tracker/features/reminders/widgets/reminder_visuals.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// One reminder with its actions. Notification taps land here.
/// The route argument is the reminder id.
class ReminderDetailView extends StatefulWidget {
  const ReminderDetailView({super.key});

  @override
  State<ReminderDetailView> createState() => _ReminderDetailViewState();
}

class _ReminderDetailViewState extends State<ReminderDetailView> {
  final ReminderController controller = Get.find<ReminderController>();

  // Read once: Get.arguments follows whichever route is on top, so reading it
  // again after opening the contact or transaction would return their id.
  late final String _id = Get.arguments is String
      ? Get.arguments as String
      : '';

  Future<void> _delete(BuildContext context, Reminder reminder) async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this reminder?'.tr,
      message: 'It will no longer alert you.'.tr,
    );
    if (confirmed && await controller.deleteReminder(reminder.id)) {
      AppSnackbar.show('Reminder deleted'.tr);
      Get.back<void>();
    }
  }

  Future<void> _snooze(BuildContext context, Reminder reminder) async {
    final SnoozeOption? option = await showModalBottomSheet<SnoozeOption>(
      context: context,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Remind me again in'.tr,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            for (final SnoozeOption o in SnoozeOption.values)
              ListTile(
                leading: const Icon(Icons.snooze_outlined),
                title: Text(o.label.tr),
                onTap: () => Navigator.of(sheet).pop(o),
              ),
          ],
        ),
      ),
    );
    if (option != null && await controller.snooze(reminder, option)) {
      AppSnackbar.show('Snoozed'.tr);
    }
  }

  Future<void> _complete(Reminder reminder) async {
    if (await controller.complete(reminder)) {
      AppSnackbar.show(
        reminder.repeat.repeats ? 'Done. Next one scheduled'.tr : 'Marked as done'.tr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final Reminder? reminder = controller.byId(_id);
      final Contact? contactEntity = reminder?.contactId == null
          ? null
          : controller.contacts.firstWhereOrNull(
              (Contact c) => c.id == reminder!.contactId,
            );
      return Scaffold(
        appBar: AppAppBar(
          title: 'Reminder'.tr,
          actions: <Widget>[
            if (reminder != null) ...<Widget>[
              if (contactEntity != null)
                IconButton(
                  tooltip: 'Send reminder via WhatsApp / SMS'.tr,
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () => SendReminderSheet.show(
                    context,
                    contact: contactEntity,
                    balance: reminder.amount ?? Decimal.zero,
                    customNote: reminder.title,
                  ),
                ),
              IconButton(
                tooltip: 'Edit reminder'.tr,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Get.toNamed<void>(
                  AppRoutes.reminderForm,
                  arguments: ReminderFormArgs(existing: reminder),
                ),
              ),
              IconButton(
                tooltip: 'Delete reminder'.tr,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, reminder),
              ),
            ],
          ],
        ),
        body: SafeArea(child: _body(context, reminder, contactEntity)),
      );
    });
  }

  Widget _body(BuildContext context, Reminder? reminder, Contact? contactEntity) {
    if (controller.isLoading.value) {
      return LoadingState(message: 'Loading reminder'.tr);
    }
    if (reminder == null) {
      final String? error = controller.error.value;
      return error != null
          ? ErrorState(message: error, onRetry: controller.load)
          : EmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'Reminder not found'.tr,
              message: 'It may have been deleted.'.tr,
            );
    }
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ReminderStatus status = ReminderCalculator.status(
      reminder,
      DateTime.now(),
    );
    final String? contact = controller.contactName(reminder.contactId);
    final String? description = reminder.description;
    final bool done = status == ReminderStatus.completed;

    return AppContent(
      child: ListView(
        children: <Widget>[
          const NotificationPermissionBanner(),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: <Widget>[
                Icon(
                  reminderIcon(reminder.type),
                  size: 32,
                  color: colors.primary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  reminder.title,
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  status.label.tr,
                  style: text.labelLarge?.copyWith(
                    color: reminderStatusColor(colors, status),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                _Row('Type'.tr, reminder.type.label.tr),
                _Row('When'.tr, AppFormatters.dateTime(reminder.remindAt)),
                if (reminder.snoozedUntil != null &&
                    status == ReminderStatus.snoozed)
                  _Row(
                    'Snoozed until'.tr,
                    AppFormatters.dateTime(reminder.snoozedUntil!),
                  ),
                _Row('Repeat'.tr, reminder.repeat.label.tr),
                if (reminder.amount != null)
                  _Row('Amount'.tr, AppFormatters.money(reminder.amount!)),
                if (reminder.contactId != null)
                  _Row(
                    'Contact'.tr,
                    contact ?? 'Contact'.tr,
                    onTap: () => Get.toNamed<void>(
                      AppRoutes.contactDetail,
                      arguments: reminder.contactId,
                    ),
                  ),
                if (reminder.transactionId != null)
                  _Row(
                    'Transaction'.tr,
                    'View transaction'.tr,
                    onTap: () => Get.toNamed<void>(
                      AppRoutes.transactionDetail,
                      arguments: reminder.transactionId,
                    ),
                  ),
                _Row(
                  'Notification'.tr,
                  reminder.notificationEnabled ? 'On'.tr : 'Off'.tr,
                ),
                if (description != null && description.isNotEmpty)
                  _Row('Notes'.tr, description),
              ],
            ),
          ),
          if (contactEntity != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text('Send Reminder (WhatsApp / SMS)'.tr),
              onPressed: () => SendReminderSheet.show(
                context,
                contact: contactEntity,
                balance: reminder.amount ?? Decimal.zero,
                customNote: reminder.title,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SubmitErrorMessage(controller.action),
          Obx(
            () => done
                ? AppButton(
                    label: 'Mark as not done'.tr,
                    icon: Icons.undo_rounded,
                    variant: AppButtonVariant.secondary,
                    isLoading: controller.action.isBusy.value,
                    onPressed: () => controller.reopen(reminder),
                  )
                : Column(
                    children: <Widget>[
                      AppButton(
                        label: 'Mark as done'.tr,
                        icon: Icons.check_rounded,
                        isLoading: controller.action.isBusy.value,
                        onPressed: () => _complete(reminder),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Snooze'.tr,
                        icon: Icons.snooze_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: controller.action.isBusy.value
                            ? null
                            : () => _snooze(context, reminder),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 110, child: Text(label, style: text.bodyMedium)),
            Expanded(
              child: Text(
                value,
                style: text.titleSmall?.copyWith(
                  color: onTap == null ? null : colors.primary,
                ),
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: colors.primary),
          ],
        ),
      ),
    );
  }
}
