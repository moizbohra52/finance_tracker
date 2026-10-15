import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:flutter/material.dart';

/// Modern contact balance card: initials squircle badge, contact name, phone,
/// and high-contrast receivable/payable badges with directional indicators.
class ContactBalanceTile extends StatelessWidget {
  const ContactBalanceTile({
    super.key,
    required this.row,
    this.onTap,
    this.padding = AppListTile.defaultPadding,
  });

  final ContactBalance row;
  final VoidCallback? onTap;

  /// Unused for card layout, preserved for API backward-compatibility.
  final EdgeInsetsGeometry padding;

  static Color _avatarColor(String name, ColorScheme colors) {
    if (name.isEmpty) return colors.primary;
    final int code = name.codeUnits.fold(0, (int sum, int c) => sum + c);
    const List<Color> palette = <Color>[
      Color(0xFF4F46E5), // Indigo
      Color(0xFF0284C7), // Sky
      Color(0xFF0D9488), // Teal
      Color(0xFF16A34A), // Green
      Color(0xFFD97706), // Amber
      Color(0xFFEA580C), // Orange
      Color(0xFFE11D48), // Rose
      Color(0xFF9333EA), // Purple
    ];
    return palette[code % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final String name = row.contact.name.trim();
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final Color avatarCol = _avatarColor(name, colors);

    final bool isRec = row.isReceivable;
    final bool isPay = row.isPayable;
    final Color? statusColor = isRec
        ? money.receivable
        : isPay
        ? money.payable
        : null;

    final String statusLabel = isRec
        ? 'YOU WILL GET'
        : isPay
        ? 'YOU WILL GIVE'
        : 'SETTLED';

    final IconData statusIcon = isRec
        ? Icons.arrow_downward_rounded
        : isPay
        ? Icons.arrow_upward_rounded
        : Icons.check_circle_outline_rounded;

    final String? mobile = row.contact.mobile?.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
            width: 1,
          ),
        ),
        elevation: isDark ? 0 : 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // Avatar Squircle
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: avatarCol.withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: avatarCol,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Contact Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (mobile != null && mobile.isNotEmpty)
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.phone_outlined,
                              size: 11.5,
                              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                mobile,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'No phone number',
                          style: text.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                            fontStyle: FontStyle.italic,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Balance & Status Pill
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (statusColor != null)
                      Text(
                        '${isRec ? '+' : '-'}${AppFormatters.money(row.balance.abs())}',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (statusColor ?? colors.onSurfaceVariant)
                            .withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            statusIcon,
                            size: 10,
                            color: statusColor ?? colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: statusColor ?? colors.onSurfaceVariant,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
