import 'package:finance_tracker/core/services/backup_service.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/features/backup/controllers/backup_controller.dart';
import 'package:finance_tracker/features/backup/widgets/backup_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BackupView extends GetView<BackupController> {
  const BackupView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: 'Backup & Restore'.tr),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxPageWidth,
          child: ListView(
            children: <Widget>[
              SectionHeader(title: 'Create Backup'.tr),
              const SizedBox(height: AppSpacing.sm),
              _buildBackupCard(context),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(title: 'Restore Data'.tr),
              const SizedBox(height: AppSpacing.sm),
              _buildRestoreCard(context),
              const SizedBox(height: AppSpacing.lg),
              InlineMessage(
                tone: InlineMessageTone.info,
                icon: Icons.shield_outlined,
                title: 'Data Security & Privacy'.tr,
                message:
                    'Your backups are generated locally on this device. Passwords, login tokens, and authentication secrets are strictly excluded. You can store your backup file securely on Google Drive, iCloud, or external storage.'
                        .tr,
                announce: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackupCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppListTile(
            padding: EdgeInsets.zero,
            leading: const IconBadge(icon: Icons.cloud_upload_outlined),
            title: 'Export Full Database Backup'.tr,
            titleMaxLines: 2,
            subtitle:
                'Packages all your accounts, transactions, khata contacts, budgets, and preferences into a standardized JSON file.'
                    .tr,
            subtitleMaxLines: 4,
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(() {
            final bool backingUp = controller.isCreatingBackup.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Status(
                  visible: backingUp,
                  message: controller.statusMessage.value,
                ),
                AppButton(
                  label: backingUp
                      ? 'Creating Backup...'.tr
                      : 'Create & Share Backup'.tr,
                  icon: Icons.download_rounded,
                  isLoading: backingUp,
                  onPressed: () => controller.createBackupAndShare(),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRestoreCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppListTile(
            padding: EdgeInsets.zero,
            leading: IconBadge(
              icon: Icons.restore_outlined,
              color: Theme.of(context).colorScheme.secondary,
            ),
            title: 'Restore from JSON Backup'.tr,
            titleMaxLines: 2,
            subtitle:
                'Select a previously generated backup file. You can preview all records and choose to merge or replace existing data.'
                    .tr,
            subtitleMaxLines: 4,
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(() {
            final bool restoring = controller.isRestoring.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Status(
                  visible: restoring,
                  message: controller.statusMessage.value,
                ),
                AppButton(
                  label: restoring
                      ? 'Restoring Data...'.tr
                      : 'Select Backup File (.json)'.tr,
                  icon: Icons.file_open_outlined,
                  variant: AppButtonVariant.secondary,
                  isLoading: restoring,
                  onPressed: _restore,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    final BackupValidationResult? validation = await controller
        .pickAndValidateBackup();
    if (validation == null) return;

    if (!validation.isValid) {
      await Get.dialog<void>(
        AlertDialog(
          title: Text('Invalid Backup File'.tr),
          content: Text(
            validation.errorMessage ?? 'The file could not be validated.'.tr,
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Get.back<void>(), child: Text('OK'.tr)),
          ],
        ),
      );
      return;
    }

    // Show preview dialog
    await Get.dialog<void>(
      BackupPreviewDialog(
        validation: validation,
        onConfirm: (bool replaceExisting) {
          controller.executeRestore(
            validationResult: validation,
            replaceExisting: replaceExisting,
          );
        },
      ),
    );
  }
}

/// Progress text above a card's button while its job runs.
class _Status extends StatelessWidget {
  const _Status({required this.visible, required this.message});

  final bool visible;

  /// Read inside the parent's Obx, so a new message rebuilds this.
  final String message;

  @override
  Widget build(BuildContext context) {
    if (!visible || message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
