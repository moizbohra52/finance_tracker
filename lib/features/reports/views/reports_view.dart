import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/chart_palette.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/category_breakdown.dart';
import 'package:finance_tracker/core/widgets/charts.dart';
import 'package:finance_tracker/core/widgets/date_filter_bar.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/report_calculator.dart';
import 'package:finance_tracker/features/reports/controllers/reports_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Standalone reports route (back-navigable from the dashboard).
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    appBar: AppAppBar(title: 'Reports'),
    body: SafeArea(child: ReportsView()),
  );
}

/// Reports and analytics for the selected period. Shared by the Reports tab
/// and the standalone route.
class ReportsView extends GetView<ReportsController> {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const AppContent(child: SkeletonList(count: 5));
      }
      final String? error = controller.error.value;
      if (error != null && controller.transactionCount.value == 0) {
        return LoadFailureView(message: error, onRetry: controller.load);
      }
      return RefreshIndicator(
        onRefresh: () => controller.load(force: true),
        child: AppContent(
          maxWidth: AppSizes.maxPageWidth,
          child: ListView(
            children: <Widget>[
              DateFilterBar(
                period: controller.period.value,
                onPreset: controller.selectPreset,
                onCustom: controller.selectCustom,
              ),
              const SizedBox(height: AppSpacing.md),
              const _Totals(),
              const SizedBox(height: AppSpacing.lg),
              const _TrendCard(),
              const SizedBox(height: AppSpacing.md),
              const _CategoryCard(),
              const SizedBox(height: AppSpacing.md),
              const _AccountCard(),
              const SizedBox(height: AppSpacing.md),
              const _MonthlyCard(),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      );
    });
  }
}

class _Totals extends GetView<ReportsController> {
  const _Totals();

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    return Obx(() {
      final PeriodSummary s = controller.summary.value;
      final bool positive = s.net >= Decimal.zero;
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SummaryTile(
                  icon: Icons.south_west_rounded,
                  label: 'Income',
                  value: AppFormatters.money(s.income),
                  color: money.income,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SummaryTile(
                  icon: Icons.north_east_rounded,
                  label: 'Expense',
                  value: AppFormatters.money(s.expense),
                  color: money.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SummaryTile(
            icon: positive
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            label: 'Net change',
            value: AppFormatters.signedMoney(s.net, positive: positive),
            color: positive ? money.income : money.expense,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: SummaryTile(
                  icon: Icons.call_received_rounded,
                  label: 'Receivable',
                  value: AppFormatters.money(controller.khata.value.receivable),
                  color: money.receivable,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SummaryTile(
                  icon: Icons.call_made_rounded,
                  label: 'Payable',
                  value: AppFormatters.money(controller.khata.value.payable),
                  color: money.payable,
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

/// Card with a header and either [child] or an empty state.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.hasData,
    required this.emptyMessage,
    required this.child,
    this.trailing,
  });

  final String title;
  final bool hasData;
  final String emptyMessage;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: title),
          if (trailing != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            trailing!,
          ],
          const SizedBox(height: AppSpacing.sm),
          if (hasData)
            child
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: EmptyState(
                icon: Icons.bar_chart_rounded,
                title: 'Nothing to show yet',
                message: emptyMessage,
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendCard extends GetView<ReportsController> {
  const _TrendCard();

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    return Obx(
      () => _ChartCard(
        title: 'Income vs expense',
        hasData: controller.hasData,
        emptyMessage: 'No income or expense in this period.',
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 200,
              child: TrendLineChart(
                points: controller.trend.toList(),
                bucket: controller.bucket,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              children: <Widget>[
                LegendDot(color: money.income, label: 'Income'),
                LegendDot(color: money.expense, label: 'Expense'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends GetView<ReportsController> {
  const _CategoryCard();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final bool isExpense =
          controller.categoryType.value == TransactionType.expense;
      final List<CategoryTotal> totals = controller.categoryTotals.toList();
      final Decimal total = totals.fold(
        Decimal.zero,
        (Decimal sum, CategoryTotal t) => sum + t.amount,
      );
      return _ChartCard(
        title: isExpense ? 'Spending by category' : 'Income by category',
        hasData: totals.isNotEmpty,
        emptyMessage: isExpense
            ? 'No expenses in this period.'
            : 'No income in this period.',
        trailing: SegmentedButton<TransactionType>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const <ButtonSegment<TransactionType>>[
            ButtonSegment<TransactionType>(
              value: TransactionType.expense,
              label: Text('Expense'),
            ),
            ButtonSegment<TransactionType>(
              value: TransactionType.income,
              label: Text('Income'),
            ),
          ],
          selected: <TransactionType>{controller.categoryType.value},
          onSelectionChanged: (Set<TransactionType> s) =>
              controller.selectCategoryType(s.first),
        ),
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 190,
              child: ShareDonut(
                shares: <double>[for (final CategoryTotal t in totals) t.share],
                colors: <Color>[
                  for (int i = 0; i < totals.length; i++)
                    ChartPalette.at(context, i),
                ],
                centerLabel: isExpense ? 'Spent' : 'Earned',
                centerValue: AppFormatters.money(total),
              ),
            ),
            CategoryBreakdown(
              rows: <BreakdownRow>[
                for (int i = 0; i < totals.length; i++)
                  _row(context, totals[i], i),
              ],
            ),
          ],
        ),
      );
    });
  }

  BreakdownRow _row(BuildContext context, CategoryTotal t, int index) {
    final Category? category = controller.categoryOf(t.categoryId);
    return BreakdownRow(
      label: category?.name ?? 'Uncategorised',
      icon: CategoryIcons.of(category?.icon, controller.categoryType.value),
      amount: AppFormatters.money(t.amount),
      share: t.share,
      color: ChartPalette.at(context, index),
    );
  }
}

class _AccountCard extends GetView<ReportsController> {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Obx(
      () => _ChartCard(
        title: 'By account',
        hasData: controller.accountTotals.isNotEmpty,
        emptyMessage: 'No account activity in this period.',
        child: Column(
          children: <Widget>[
            for (final AccountTotal a in controller.accountTotals)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(controller.accountName(a.accountId)),
                subtitle: Text(
                  '+${AppFormatters.money(a.income)}  ·  '
                  '−${AppFormatters.money(a.expense)}',
                  style: text.bodySmall,
                ),
                trailing: Text(
                  AppFormatters.signedMoney(
                    a.net,
                    positive: a.net >= Decimal.zero,
                  ),
                  style: text.titleSmall?.copyWith(
                    color: a.net >= Decimal.zero ? money.income : money.expense,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyCard extends GetView<ReportsController> {
  const _MonthlyCard();

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    return Obx(() {
      final List<TrendPoint> points = controller.monthly.toList();
      final bool hasData = points.any(
        (TrendPoint p) => p.income > Decimal.zero || p.expense > Decimal.zero,
      );
      return _ChartCard(
        title: 'Monthly comparison',
        hasData: hasData,
        emptyMessage: 'Add transactions to compare the last 6 months.',
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 200,
              child: IncomeExpenseBarChart(
                points: points,
                bucket: TrendBucket.month,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              children: <Widget>[
                LegendDot(color: money.income, label: 'Income'),
                LegendDot(color: money.expense, label: 'Expense'),
              ],
            ),
          ],
        ),
      );
    });
  }
}
