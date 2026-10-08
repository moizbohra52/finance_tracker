import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/core/widgets/sync_status_sheet.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Interactive sync & offline status banner.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final SyncEngine? syncEngine = Get.isRegistered<SyncEngine>()
        ? Get.find<SyncEngine>()
        : null;

    final int pending = syncEngine?.pendingCount.value ?? 0;

    return Semantics(
      liveRegion: true,
      label: 'Offline. Changes saved locally.',
      child: Material(
        color: colors.surfaceContainerHighest,
        child: InkWell(
          onTap: () => showSyncStatusSheet(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Offline — changes saved locally',
                    style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (pending > 0) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$pending pending',
                      style: text.labelSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dynamic sync status bar that reflects offline, waiting, syncing, and error states.
class SyncStatusBar extends StatelessWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ConnectivityService? connectivity =
        Get.isRegistered<ConnectivityService>()
        ? Get.find<ConnectivityService>()
        : null;
    final SyncEngine? syncEngine = Get.isRegistered<SyncEngine>()
        ? Get.find<SyncEngine>()
        : null;

    if (syncEngine == null) {
      return Obx(
        () => (connectivity?.isOffline ?? false)
            ? const OfflineBanner()
            : const SizedBox.shrink(),
      );
    }

    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Obx(() {
      final bool isOffline = connectivity?.isOffline ?? false;
      final SyncState state = syncEngine.state.value;
      final int pending = syncEngine.pendingCount.value;

      if (isOffline) {
        return const OfflineBanner();
      }

      if (state == SyncState.syncing) {
        return Container(
          width: double.infinity,
          color: colors.primaryContainer.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Syncing changes with cloud...',
                  style: text.bodySmall?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      if (state == SyncState.error) {
        return Material(
          color: colors.errorContainer,
          child: InkWell(
            onTap: () => showSyncStatusSheet(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 6,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.sync_problem_rounded,
                    size: 16,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Sync failed · $pending changes pending',
                      style: text.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    'Details',
                    style: text.labelSmall?.copyWith(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: colors.onErrorContainer,
                  ),
                ],
              ),
            ),
          ),
        );
      }

      if (state == SyncState.waiting && pending > 0) {
        return Material(
          color: colors.surfaceContainerHighest,
          child: InkWell(
            onTap: () => showSyncStatusSheet(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 6,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '$pending changes waiting to sync',
                      style: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    'Sync now',
                    style: text.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return const SizedBox.shrink();
    });
  }
}

/// Full-page offline state for screens that cannot show cached content.
class OfflineState extends StatelessWidget {
  const OfflineState({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.maxContentWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'You’re offline',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Connect to a network and try again.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (onRetry != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Try again',
                  variant: AppButtonVariant.secondary,
                  isExpanded: false,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Failure view that says "offline" when the device has no network, and
/// shows the mapped [message] otherwise.
class LoadFailureView extends StatelessWidget {
  const LoadFailureView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bool offline =
        Get.isRegistered<ConnectivityService>() &&
        Get.find<ConnectivityService>().isOffline;
    return offline
        ? OfflineState(onRetry: onRetry)
        : ErrorState(message: message, onRetry: onRetry);
  }
}
