import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:flutter/material.dart';

/// Centered progress indicator for full-area loading. Lists and the
/// dashboard should prefer skeletons once those layouts exist.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final String? message = this.message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(semanticsLabel: message ?? 'Loading'),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tells the user there is nothing here yet and, ideally, what to do next.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'actionLabel and onAction must be provided together',
       );

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _StatusMessage(
      icon: icon,
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

/// User-friendly failure message with an optional retry. Pass a message
/// already mapped from the underlying error, never a raw exception string.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _StatusMessage(
      icon: Icons.error_outline,
      iconColor: Theme.of(context).colorScheme.error,
      title: title,
      message: message,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String? actionLabel = this.actionLabel;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.maxContentWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: AppSizes.iconLarge, color: iconColor),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
              if (actionLabel != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: actionLabel,
                  onPressed: onAction,
                  variant: AppButtonVariant.secondary,
                  isExpanded: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
