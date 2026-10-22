// ignore_for_file: deprecated_member_use
import 'package:finance_tracker/core/services/backup_service.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// Modal dialog showing preview of records in a backup file before restoration.
/// Prompts the user to select between 'Merge' and 'Replace' mode and confirms before applying changes.
class BackupPreviewDialog extends StatefulWidget {
  const BackupPreviewDialog({
    super.key,
    required this.validation,
    required this.onConfirm,
  });

  final BackupValidationResult validation;
  final void Function(bool replaceExisting) onConfirm;

  @override
  State<BackupPreviewDialog> createState() => _BackupPreviewDialogState();
}

class _BackupPreviewDialogState extends State<BackupPreviewDialog> {
  bool _replaceExisting = false;
  bool _confirmedWarning = false;

  /// A tick given for one mode never confirms the other, so switching to the
  /// destructive replace always asks again.
  void _selectMode(bool replace) => setState(() {
    if (replace != _replaceExisting) _confirmedWarning = false;
    _replaceExisting = replace;
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final BackupValidationResult v = widget.validation;

    final String dateStr = v.createdAt != null
        ? DateFormat('MMM dd, yyyy · hh:mm a').format(v.createdAt!.toLocal())
        : 'Unknown'.tr;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.restore_page_outlined),
          const SizedBox(width: AppSpacing.sm),
          Text('Backup Preview'.tr),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Meta info
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withAlpha(100),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Created: @date'.trParams(<String, String>{
                        'date': dateStr,
                      }),
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      'Total Records: @count'.trParams(<String, String>{
                        'count': '${v.totalRecords}',
                      }),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              Text(
                'Records in this backup:'.tr,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),

              // Table counts list
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  children: v.tableCounts.entries
                      .where((entry) => entry.value > 0)
                      .map((entry) {
                        final String friendlyName = _friendlyTableName(
                          entry.key,
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(friendlyName),
                              Text(
                                '${entry.value}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // Restore Mode Selection
              Text('Restore Mode:'.tr, style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),

              RadioListTile<bool>(
                value: false,
                groupValue: _replaceExisting,
                onChanged: (bool? val) => _selectMode(val ?? false),
                title: Text('Merge with existing data'.tr),
                subtitle: Text(
                  'Keeps your current data, updating matching items and adding new ones. Changes also sync to your cloud account.'
                      .tr,
                ),
                contentPadding: EdgeInsets.zero,
              ),

              RadioListTile<bool>(
                value: true,
                groupValue: _replaceExisting,
                onChanged: (bool? val) => _selectMode(val ?? true),
                title: Text(
                  'Clean restore (Replace all data)'.tr,
                  style: TextStyle(
                    color: _replaceExisting ? colors.error : null,
                  ),
                ),
                subtitle: Text(
                  'Deletes all your current entries on this device and in your cloud account, including other devices, then restores the backup.'
                      .tr,
                ),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: AppSpacing.sm),

              // Confirmation Checkbox
              CheckboxListTile(
                value: _confirmedWarning,
                onChanged: (bool? val) {
                  setState(() => _confirmedWarning = val ?? false);
                },
                title: Text(
                  _replaceExisting
                      ? 'I understand that my current data will be deleted from this device and the cloud, and replaced.'
                            .tr
                      : 'I want to proceed with merging this backup data.'.tr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          onPressed: _confirmedWarning
              ? () {
                  Navigator.of(context).pop();
                  widget.onConfirm(_replaceExisting);
                }
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: _replaceExisting ? colors.error : null,
          ),
          child: Text(
            _replaceExisting ? 'Replace & Restore'.tr : 'Restore Data'.tr,
          ),
        ),
      ],
    );
  }

  String _friendlyTableName(String table) {
    switch (table) {
      case 'accounts':
        return 'Accounts'.tr;
      case 'transactions':
        return 'Transactions'.tr;
      case 'categories':
        return 'Categories'.tr;
      case 'contacts':
        return 'Khata Contacts'.tr;
      case 'contact_transactions':
        return 'Khata Transactions'.tr;
      case 'budgets':
        return 'Budgets'.tr;
      case 'recurring_transactions':
        return 'Recurring Plans'.tr;
      case 'reminders':
        return 'Reminders'.tr;
      case 'user_settings':
        return 'Preferences & Settings'.tr;
      case 'profiles':
        return 'Profile'.tr;
      default:
        return table;
    }
  }
}
