import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';

/// One labelled row of a breakdown list.
class BreakdownRow {
  const BreakdownRow({
    required this.label,
    required this.icon,
    required this.amount,
    required this.share,
    required this.color,
  });

  final String label;
  final IconData icon;
  final String amount;

  /// 0..1
  final double share;
  final Color color;
}

/// Category (or account) list with a share bar and percentage. The bar is
/// paired with the figures, so colour is never the only signal.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({super.key, required this.rows});

  final List<BreakdownRow> rows;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        for (final BreakdownRow r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: r.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(r.icon, size: 20, color: r.color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              r.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            r.amount,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: AppProgressBar(
                              value: r.share,
                              color: r.color,
                              height: 6,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 44,
                            child: Text(
                              '${AppFormatters.number(r.share * 100, decimalDigits: 0)}%',
                              textAlign: TextAlign.end,
                              style: text.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
