import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
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
    return Column(
      children: <Widget>[
        for (final BreakdownRow r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: r.color.withValues(alpha: 0.15),
                  child: Icon(r.icon, size: 18, color: r.color),
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
                              style: text.titleSmall,
                            ),
                          ),
                          Text(r.amount, style: text.titleSmall),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: r.share.clamp(0, 1),
                                minHeight: 6,
                                color: r.color,
                                backgroundColor: r.color.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${AppFormatters.number(r.share * 100, decimalDigits: 0)}%',
                              textAlign: TextAlign.end,
                              style: text.labelSmall,
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
