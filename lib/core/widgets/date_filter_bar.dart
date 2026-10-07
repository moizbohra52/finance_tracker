import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/domain/services/report_period.dart';
import 'package:flutter/material.dart';

/// Reusable period selector: preset chips plus a custom range picker.
/// Stateless; the owner holds the [period] and reacts to the callbacks.
class DateFilterBar extends StatelessWidget {
  const DateFilterBar({
    super.key,
    required this.period,
    required this.onPreset,
    required this.onCustom,
  });

  final ReportPeriod period;
  final ValueChanged<DatePreset> onPreset;

  /// Receives inclusive first and last days.
  final void Function(DateTime start, DateTime end) onCustom;

  Future<void> _pickRange(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: period.preset == DatePreset.custom
          ? DateTimeRange(start: period.start, end: period.lastDay)
          : null,
    );
    if (picked != null) onCustom(picked.start, picked.end);
  }

  String get _label {
    final String first = AppFormatters.date(period.start);
    return period.days <= 1
        ? first
        : '$first – ${AppFormatters.date(period.lastDay)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final DatePreset p in DatePreset.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(p.label),
                    labelStyle: TextStyle(
                      fontWeight: period.preset == p
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    avatar: p == DatePreset.custom
                        ? const Icon(Icons.date_range_outlined, size: 18)
                        : null,
                    selected: period.preset == p,
                    onSelected: (_) => p == DatePreset.custom
                        ? _pickRange(context)
                        : onPreset(p),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          _label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
