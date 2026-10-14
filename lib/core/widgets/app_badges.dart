import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Tinted circle holding an icon or a short label such as a name's initial.
/// It is the leading mark of list rows, tiles, quick actions and empty
/// states, so every screen shares one shape and one tint strength.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required IconData this.icon,
    this.color,
    this.background,
    this.size = AppSizes.iconBadge,
  }) : label = null;

  /// The first letter of [name], or '?' when it is empty.
  IconBadge.initial(
    String name, {
    super.key,
    this.color,
    this.background,
    this.size = AppSizes.iconBadge,
  }) : icon = null,
       label = name.trim().isEmpty
           ? '?'
           : name.trim().characters.first.toUpperCase();

  final IconData? icon;
  final String? label;

  /// Icon/label colour; the fill is a light tint of it. Defaults to primary.
  final Color? color;

  /// Overrides the tinted fill, for badges on a coloured surface.
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color tint = color ?? Theme.of(context).colorScheme.primary;
    final String? label = this.label;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background ?? tint.withValues(alpha: 0.12),
      ),
      child: label == null
          ? Icon(icon, size: size * 0.5, color: tint)
          : Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tint,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

/// Small rounded label for a state such as "Over budget" or "Overdue". It
/// carries text (and optionally an icon), so meaning never rests on colour.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final IconData? icon = this.icon;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
