import 'package:flutter/material.dart';

/// [destructive] is for irreversible actions (always behind a confirmation).
enum AppButtonVariant { primary, secondary, destructive }

/// Standard action button. While [isLoading] it is disabled and shows a
/// spinner next to the label, so double submits are impossible and screen
/// readers still announce the action.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.isExpanded = true,
  });

  final String label;

  /// Null renders the button disabled.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? action = isLoading ? null : onPressed;
    final Widget? leading = isLoading
        ? const _ButtonSpinner()
        : (icon == null ? null : Icon(icon));
    final Widget text = Text(label);

    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton.icon(
        onPressed: action,
        icon: leading,
        label: text,
      ),
      AppButtonVariant.secondary => OutlinedButton.icon(
        onPressed: action,
        icon: leading,
        label: text,
      ),
      AppButtonVariant.destructive => FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: action,
        icon: leading,
        label: text,
      ),
    };

    return isExpanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    // The button scopes IconTheme to its current foreground colour, so the
    // spinner matches the disabled label.
    return SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: IconTheme.of(context).color,
      ),
    );
  }
}
