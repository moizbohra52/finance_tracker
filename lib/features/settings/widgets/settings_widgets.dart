import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:flutter/material.dart';

/// Heading above a group of settings. [destructive] colours it as a warning.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {super.key, this.destructive = false});

  final String title;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: destructive ? colors.error : colors.primary,
      ),
    );
  }
}

/// One row of a settings card: an icon, a title, an optional subtitle and the
/// current value, with a chevron when it opens something.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = destructive ? colors.error : colors.primary;
    return ListTile(
      minTileHeight: AppSizes.minTouchTarget,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, size: 20, color: accent),
      ),
      title: Text(
        title,
        style: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: destructive ? colors.error : null,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (value != null)
            Flexible(
              child: Text(
                value!,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

/// A card of [children] separated by dividers.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, indent: 56));
      rows.add(children[i]);
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// Lets the user pick one of [options] from a bottom sheet. Returns the chosen
/// option, or null when the sheet is dismissed.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T? selected,
  required String Function(T option) labelOf,
  String Function(T option)? detailOf,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.maxContentWidth),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                title,
                style: Theme.of(
                  sheet,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final T option in options)
              ListTile(
                minTileHeight: AppSizes.minTouchTarget,
                title: Text(labelOf(option)),
                subtitle: detailOf == null ? null : Text(detailOf(option)),
                trailing: option == selected
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(sheet).colorScheme.primary,
                      )
                    : null,
                selected: option == selected,
                onTap: () => Navigator.of(sheet).pop(option),
              ),
          ],
        ),
      ),
    ),
  );
}
