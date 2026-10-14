import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
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

  /// Share of the row a long value may take, so the title keeps the rest.
  static const double _valueWidthShare = 0.4;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String? value = this.value;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          AppListTile(
            onTap: onTap,
            leading: IconBadge(
              icon: icon,
              color: destructive ? colors.error : colors.primary,
            ),
            title: title,
            titleStyle: destructive ? TextStyle(color: colors.error) : null,
            subtitle: subtitle,
            subtitleMaxLines: 2,
            trailing: value == null && onTap == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (value != null)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * _valueWidthShare,
                          ),
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                      if (onTap != null) ...<Widget>[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
          ),
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
