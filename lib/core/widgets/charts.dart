import 'dart:math' as math;

import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/domain/services/report_calculator.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Compact axis label: 12.5k, 3L, 2Cr. Display only.
String compactAmount(double v) {
  final double a = v.abs();
  final String sign = v < 0 ? '-' : '';
  String f(double x) =>
      x == x.roundToDouble() ? '${x.round()}' : x.toStringAsFixed(1);
  if (a >= 10000000) return '$sign${f(a / 10000000)}Cr';
  if (a >= 100000) return '$sign${f(a / 100000)}L';
  if (a >= 1000) return '$sign${f(a / 1000)}k';
  return '$sign${f(a)}';
}

String _bucketLabel(DateTime d, TrendBucket bucket) => switch (bucket) {
  TrendBucket.hour => AppFormatters.date(d, pattern: 'ha'),
  TrendBucket.day => AppFormatters.date(d, pattern: 'd'),
  TrendBucket.month => AppFormatters.date(d, pattern: 'MMM'),
};

Widget _axisLabel(BuildContext context, TitleMeta meta, String text) =>
    SideTitleWidget(
      meta: meta,
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );

FlTitlesData _titles(
  BuildContext context,
  List<TrendPoint> points,
  TrendBucket bucket,
) {
  final int step = math.max(1, (points.length / 6).ceil());
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 44,
        getTitlesWidget: (double v, TitleMeta meta) =>
            _axisLabel(context, meta, compactAmount(v)),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: 1,
        reservedSize: 28,
        getTitlesWidget: (double v, TitleMeta meta) {
          final int i = v.round();
          if (i < 0 || i >= points.length || i % step != 0) {
            return const SizedBox.shrink();
          }
          return _axisLabel(
            context,
            meta,
            _bucketLabel(points[i].start, bucket),
          );
        },
      ),
    ),
  );
}

double _maxY(List<TrendPoint> points, {bool income = true}) {
  double m = 0;
  for (final TrendPoint p in points) {
    m = math.max(m, p.expense.toDouble());
    if (income) m = math.max(m, p.income.toDouble());
  }
  return m == 0 ? 1 : m * 1.15;
}

/// Spending (and optionally income) over the period, one point per bucket.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({super.key, required this.points, required this.bucket});

  final List<TrendPoint> points;
  final TrendBucket bucket;

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final Color grid = Theme.of(context).colorScheme.outlineVariant;
    LineChartBarData line(Color color, double Function(TrendPoint) y) =>
        LineChartBarData(
          spots: <FlSpot>[
            for (int i = 0; i < points.length; i++)
              FlSpot(i.toDouble(), y(points[i])),
          ],
          isCurved: false,
          color: color,
          barWidth: 3,
          dotData: FlDotData(show: points.length <= 12),
          belowBarData: BarAreaData(
            show: true,
            color: color.withValues(alpha: 0.12),
          ),
        );
    return Semantics(
      label: 'Income and expense trend chart',
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: _maxY(points),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: grid, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context, points, bucket),
          lineBarsData: <LineChartBarData>[
            line(money.income, (TrendPoint p) => p.income.toDouble()),
            line(money.expense, (TrendPoint p) => p.expense.toDouble()),
          ],
        ),
      ),
    );
  }
}

/// Grouped income/expense bars, one group per bucket (monthly comparison).
class IncomeExpenseBarChart extends StatelessWidget {
  const IncomeExpenseBarChart({
    super.key,
    required this.points,
    required this.bucket,
  });

  final List<TrendPoint> points;
  final TrendBucket bucket;

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final Color grid = Theme.of(context).colorScheme.outlineVariant;
    BarChartRodData rod(double y, Color color) => BarChartRodData(
      toY: y,
      color: color,
      width: 10,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    );
    return Semantics(
      label: 'Income versus expense bar chart',
      child: BarChart(
        BarChartData(
          maxY: _maxY(points),
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: grid, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context, points, bucket),
          barGroups: <BarChartGroupData>[
            for (int i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: <BarChartRodData>[
                  rod(points[i].income.toDouble(), money.income),
                  rod(points[i].expense.toDouble(), money.expense),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A coloured legend dot + label used under charts.
class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// Donut of shares. [colors] and [shares] line up by index.
class ShareDonut extends StatelessWidget {
  const ShareDonut({
    super.key,
    required this.shares,
    required this.colors,
    required this.centerLabel,
    required this.centerValue,
  });

  final List<double> shares;
  final List<Color> colors;
  final String centerLabel;
  final String centerValue;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      label: '$centerLabel $centerValue breakdown chart',
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 56,
              sections: <PieChartSectionData>[
                for (int i = 0; i < shares.length; i++)
                  PieChartSectionData(
                    value: shares[i],
                    color: colors[i],
                    radius: 22,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(centerLabel, style: text.labelMedium),
              Text(
                centerValue,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
