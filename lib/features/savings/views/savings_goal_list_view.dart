import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/features/savings/controllers/savings_goal_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void openAddSavingsGoal() => Get.toNamed<void>(AppRoutes.savingsGoalForm);

class SavingsGoalListView extends GetView<SavingsGoalController> {
  const SavingsGoalListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: 'Savings goals'.tr),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const AppContent(
              child: SkeletonList(count: 4, type: SkeletonType.budget),
            );
          }
          final String? error = controller.error.value;
          if (error != null && controller.goals.isEmpty) {
            return LoadFailureView(message: error, onRetry: controller.load);
          }
          if (controller.goals.isEmpty) {
            return EmptyState(
              icon: Icons.flag_outlined,
              title: 'No savings goals yet'.tr,
              message:
                  'Pick something to save for, set a target amount and track how close you are.'
                      .tr,
              actionLabel: 'Add savings goal'.tr,
              onAction: openAddSavingsGoal,
            );
          }
          return AppContent(
            child: RefreshIndicator(
              onRefresh: controller.load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: controller.goals.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (BuildContext context, int index) =>
                    _GoalCard(goal: controller.goals[index]),
              ),
            ),
          );
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openAddSavingsGoal,
        icon: const Icon(Icons.add),
        label: Text('Add savings goal'.tr),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final SavingsGoal goal;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final bool overdue = goal.isOverdue(DateTime.now());
    final Color color = goal.isReached
        ? money.income
        : overdue
        ? money.payable
        : colors.primary;
    final DateTime? targetDate = goal.targetDate;

    return AppCard(
      onTap: () =>
          Get.toNamed<void>(AppRoutes.savingsGoalForm, arguments: goal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(icon: Icons.flag_outlined, color: color),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: Text(
                  goal.name,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (goal.isReached || overdue) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                StatusPill(
                  label: goal.isReached ? 'Goal reached'.tr : 'Overdue'.tr,
                  color: color,
                  icon: goal.isReached
                      ? Icons.check_circle_outline
                      : Icons.schedule_outlined,
                ),
              ],
            ],
          ),
          if (targetDate != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'By @date'.trParams(<String, String>{
                'date': AppFormatters.date(targetDate),
              }),
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppProgressBar(value: goal.progress, color: color),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '@spent of @amount'.trParams(<String, String>{
                    'spent': AppFormatters.money(goal.savedAmount),
                    'amount': AppFormatters.money(goal.targetAmount),
                  }),
                  style: text.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${AppFormatters.number(goal.progress * 100, decimalDigits: 0)}%',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          if (!goal.isReached) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '@amount left'.trParams(<String, String>{
                'amount': AppFormatters.money(goal.remaining),
              }),
              style: text.titleSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
