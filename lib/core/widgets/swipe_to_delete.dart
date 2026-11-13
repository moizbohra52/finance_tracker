import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Swipe a row left to delete it. [onDelete] asks first (the same
/// confirmation as the delete button), deletes, and returns whether the row
/// went: only then does it slide away, otherwise it springs back.
/// [onDismissed] takes the row out of its list at once, so it is not drawn
/// again before the list reloads. A row that cannot be deleted here passes
/// [enabled] false and does not move.
class SwipeToDelete extends StatelessWidget {
  const SwipeToDelete({
    required Key super.key,
    required this.onDelete,
    required this.onDismissed,
    required this.child,
    this.enabled = true,
    this.margin = EdgeInsets.zero,
  });

  final Future<bool> Function() onDelete;
  final VoidCallback onDismissed;
  final Widget child;
  final bool enabled;

  /// Keeps the red background inside a row that has its own outer spacing
  /// (a card with a gap above and below).
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete(),
      onDismissed: (_) => onDismissed(),
      background: Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: colors.error,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.delete_outline, color: colors.onError),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Delete'.tr,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: colors.onError),
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}
