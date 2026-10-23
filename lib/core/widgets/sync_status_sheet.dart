import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Opens the Sync Status modal bottom sheet.
Future<void> showSyncStatusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => const SyncStatusSheet(),
  );
}

class SyncStatusSheet extends StatefulWidget {
  const SyncStatusSheet({super.key});

  @override
  State<SyncStatusSheet> createState() => _SyncStatusSheetState();
}

class _SyncStatusSheetState extends State<SyncStatusSheet> {
  List<SyncQueueItem> _items = <SyncQueueItem>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    if (!Get.isRegistered<SyncEngine>()) {
      setState(() => _isLoading = false);
      return;
    }
    final SyncEngine engine = Get.find<SyncEngine>();
    final List<SyncQueueItem> items = await engine.getPendingItems();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final SyncEngine? engine = Get.isRegistered<SyncEngine>()
        ? Get.find<SyncEngine>()
        : null;
    final ConnectivityService? connectivity =
        Get.isRegistered<ConnectivityService>()
        ? Get.find<ConnectivityService>()
        : null;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'Sync Status'.tr,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (engine != null)
                Obx(() {
                  final SyncState state = engine.state.value;
                  final bool isOffline = connectivity?.isOffline ?? false;
                  final DateTime? lastSync = engine.lastSyncedAt.value;

                  return AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              isOffline
                                  ? Icons.cloud_off_outlined
                                  : state == SyncState.syncing
                                  ? Icons.sync_rounded
                                  : state == SyncState.error
                                  ? Icons.sync_problem_rounded
                                  : Icons.cloud_done_outlined,
                              color: isOffline
                                  ? colors.error
                                  : state == SyncState.error
                                  ? colors.error
                                  : colors.primary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    isOffline
                                        ? 'Offline'.tr
                                        : state == SyncState.syncing
                                        ? 'Syncing with cloud...'.tr
                                        : state == SyncState.error
                                        ? 'Sync Error'.tr
                                        : 'In Sync'.tr,
                                    style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    lastSync != null
                                        ? 'Last synced @date'.trParams(
                                            <String, String>{
                                              'date': AppFormatters.date(
                                                lastSync,
                                              ),
                                            },
                                          )
                                        : 'Not synced yet'.tr,
                                    style: text.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isOffline && state != SyncState.syncing)
                              AppButton(
                                label: 'Sync now'.tr,
                                variant: AppButtonVariant.secondary,
                                isExpanded: false,
                                onPressed: () async {
                                  await engine.syncAll();
                                  await _loadQueue();
                                },
                              ),
                          ],
                        ),
                        if (engine.lastError.value != null) ...<Widget>[
                          const SizedBox(height: AppSpacing.sm),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: colors.errorContainer,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              engine.lastError.value!,
                              style: text.bodySmall?.copyWith(
                                color: colors.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Pending Queue (@count)'.trParams(<String, String>{
                  'count': '${_items.length}',
                }),
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.done_all_rounded,
                              size: 44,
                              color: colors.primary.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'All changes are synced'.tr,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'No pending operations in the sync queue.'.tr,
                              style: text.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: _items.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const Divider(height: 1, indent: 48),
                        itemBuilder: (BuildContext context, int index) {
                          final SyncQueueItem item = _items[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: _operationColor(
                                item.operation,
                                colors,
                              ).withValues(alpha: 0.15),
                              child: Icon(
                                _entityIcon(item.entity),
                                size: 16,
                                color: _operationColor(item.operation, colors),
                              ),
                            ),
                            title: Text(
                              _operationTitle(item.operation, item.entity),
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Queued @date'.trParams(<String, String>{
                                    'date': AppFormatters.date(item.createdAt),
                                  }) +
                                  (item.retryCount > 0
                                      ? ' · ${'@count retries'.trParams(<String, String>{'count': '${item.retryCount}'})}'
                                      : ''),
                              style: text.bodySmall?.copyWith(
                                color: item.status == SyncItemStatus.failed
                                    ? colors.error
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                            trailing: Chip(
                              label: Text(
                                item.status.name.toUpperCase(),
                                style: text.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  Color _operationColor(SyncOperation op, ColorScheme colors) {
    switch (op) {
      case SyncOperation.create:
        return Colors.green;
      case SyncOperation.update:
        return Colors.blue;
      case SyncOperation.delete:
      case SyncOperation.replace:
        return colors.error;
    }
  }

  IconData _entityIcon(String entity) {
    switch (entity) {
      case 'transactions':
        return Icons.receipt_long_outlined;
      case 'accounts':
        return Icons.account_balance_wallet_outlined;
      case 'contacts':
      case 'contact_transactions':
        return Icons.people_outline;
      case 'budgets':
        return Icons.savings_outlined;
      case 'recurring_transactions':
        return Icons.event_repeat_outlined;
      case 'reminders':
        return Icons.notifications_active_outlined;
      case 'savings_goals':
        return Icons.flag_outlined;
      case 'categories':
        return Icons.category_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  String _formatEntityName(String entity) {
    switch (entity) {
      case 'transactions':
        return 'Transaction'.tr;
      case 'accounts':
        return 'Account'.tr;
      case 'contacts':
        return 'Contact'.tr;
      case 'contact_transactions':
        return 'Khata Entry'.tr;
      case 'budgets':
        return 'Budget'.tr;
      case 'recurring_transactions':
        return 'Recurring Rule'.tr;
      case 'reminders':
        return 'Reminder'.tr;
      case 'savings_goals':
        return 'Savings goal'.tr;
      case 'categories':
        return 'Category'.tr;
      case 'user_settings':
        return 'Settings'.tr;
      default:
        return entity;
    }
  }

  /// "Create Transaction"; each operation has its own key because the word
  /// order differs in Hindi.
  String _operationTitle(SyncOperation op, String entity) {
    final Map<String, String> params = <String, String>{
      'entity': _formatEntityName(entity),
    };
    return switch (op) {
      SyncOperation.create => 'Create @entity'.trParams(params),
      SyncOperation.update => 'Update @entity'.trParams(params),
      SyncOperation.delete => 'Delete @entity'.trParams(params),
      SyncOperation.replace => 'Replace @entity'.trParams(params),
    };
  }
}
