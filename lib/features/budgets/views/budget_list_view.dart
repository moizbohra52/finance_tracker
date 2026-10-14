import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/budget.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/budget_calculator.dart';
import 'package:finance_tracker/features/budgets/controllers/budget_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void openAddBudget() => Get.toNamed<void>(AppRoutes.budgetForm);

class BudgetListView extends GetView<BudgetController> {
  const BudgetListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Budgets'),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const AppContent(
              child: SkeletonList(count: 4, type: SkeletonType.budget),
            );
          }
          final String? error = controller.error.value;
          if (error != null && controller.statuses.isEmpty) {
            return LoadFailureView(message: error, onRetry: controller.load);
          }
          if (controller.statuses.isEmpty) {
            return const EmptyState(
              icon: Icons.savings_outlined,
              title: 'No budgets yet',
              message:
                  'Set a monthly or custom limit for all spending or for one '
                  'category, and see how much is left.',
              actionLabel: 'Add budget',
              onAction: openAddBudget,
            );
          }
          return AppContent(
            child: RefreshIndicator(
              onRefresh: controller.load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: controller.statuses.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (BuildContext context, int index) =>
                    _BudgetCard(status: controller.statuses[index]),
              ),
            ),
          );
        }),
      ),
      floatingActionButton: const FloatingActionButton.extended(
        onPressed: openAddBudget,
        icon: Icon(Icons.add),
        label: Text('Add budget'),
      ),
    );
  }
}

class _BudgetCard extends GetView<BudgetController> {
  const _BudgetCard({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final Budget budget = status.budget;
    final (Color color, String label, IconData icon) = switch (status.level) {
      BudgetLevel.ok => (
        colors.primary,
        'On track',
        Icons.check_circle_outline,
      ),
      BudgetLevel.warning75 => (
        money.payable,
        '75% used',
        Icons.warning_amber_rounded,
      ),
      BudgetLevel.warning90 => (
        money.payable,
        '90% used',
        Icons.warning_amber_rounded,
      ),
      BudgetLevel.exceeded => (
        money.expense,
        'Over budget',
        Icons.error_outline,
      ),
    };
    final String period = budget.periodType == BudgetPeriodType.monthly
        ? AppFormatters.date(status.period.start, pattern: 'MMMM y')
        : '${AppFormatters.date(status.period.start)} – '
              '${AppFormatters.date(status.period.lastDay)}';
    final String stateNote = switch (status.state) {
      BudgetState.upcoming =>
        'Starts ${AppFormatters.date(status.period.start)}',
      BudgetState.ended => 'Ended',
      BudgetState.active => period,
    };
    final bool over = status.remaining < Decimal.zero;

    return AppCard(
      onTap: () => Get.toNamed<void>(AppRoutes.budgetForm, arguments: budget),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(
                icon: CategoryIcons.of(
                  controller.categoryOf(budget.categoryId)?.icon,
                  TransactionType.expense,
                ),
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: Text(
                  controller.nameOf(budget),
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusPill(label: label, color: color, icon: icon),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            stateNote,
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          AppProgressBar(value: status.percent / 100, color: color),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${AppFormatters.money(status.spent)} of '
                  '${AppFormatters.money(budget.amount)}',
                  style: text.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${AppFormatters.number(status.percent, decimalDigits: 0)}%',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            over
                ? 'Over by ${AppFormatters.money(status.remaining.abs())}'
                : '${AppFormatters.money(status.remaining)} left',
            style: text.titleSmall?.copyWith(
              color: over ? money.expense : colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
