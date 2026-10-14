import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:flutter/material.dart';

/// The one row layout for lists: a leading mark (usually an IconBadge), a
/// title, up to two lines of detail and a trailing value. Transactions,
/// contacts, accounts, reminders and settings all use it, so rows line up
/// and read the same on every screen.
///
/// Unlike ListTile it does not cap the trailing height, so a trailing amount
/// can sit above a Switch.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.leading,
    required this.title,
    this.titleMaxLines = 1,
    this.subtitle,
    this.subtitleMaxLines = 1,
    this.caption,
    this.trailing,
    this.titleStyle,
    this.onTap,
    this.padding = defaultPadding,
  });

  /// Rows inside a card, whose edge is the card's.
  static const EdgeInsets defaultPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm + AppSpacing.xs,
  );

  /// Rows directly on the page, which already has a side gutter.
  static const EdgeInsets flatPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.sm + AppSpacing.xs,
  );

  /// Where a row's text starts with [defaultPadding] and a standard badge,
  /// so dividers between rows line up with it.
  static const double textInset =
      AppSpacing.md + AppSizes.iconBadge + AppSpacing.md;

  final Widget leading;
  final String title;
  final int titleMaxLines;
  final String? subtitle;
  final int subtitleMaxLines;

  /// Third line, such as a StatusPill.
  final Widget? caption;
  final Widget? trailing;

  /// Merged over the default title style (e.g. bold when unread).
  final TextStyle? titleStyle;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String? subtitle = this.subtitle;
    final Widget? caption = this.caption;
    final Widget? trailing = this.trailing;

    final Widget row = Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        child: Row(
          children: <Widget>[
            leading,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)
                        .merge(titleStyle),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      maxLines: subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (caption != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    caption,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              trailing,
            ],
          ],
        ),
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// A card of rows (usually [AppListTile]s) separated by dividers that line
/// up with the rows' text.
class AppListCard extends StatelessWidget {
  const AppListCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          const Divider(
            height: 1,
            indent: AppListTile.textInset,
            endIndent: AppSpacing.md,
          ),
        );
      }
      rows.add(children[i]);
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}
