import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/features/savings/controllers/savings_goal_controller.dart';
import 'package:finance_tracker/features/savings/controllers/savings_goal_detail_controller.dart';
import 'package:finance_tracker/features/savings/widgets/add_money_sheet.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// One savings goal: where it stands, Add money, and its history.
class SavingsGoalDetailView extends GetView<SavingsGoalDetailController> {
  const SavingsGoalDetailView({super.key, required this.goalId});

  final String goalId;

  @override
  String get tag => goalId;

  @override
  Widget build(BuildContext context) {
    final SavingsGoalController goals = Get.find<SavingsGoalController>();
    return Obx(() {
      final SavingsGoal? goal = goals.byId(goalId);
      return Scaffold(
        appBar: AppAppBar(
          title: goal?.name ?? 'Savings goal'.tr,
          actions: <Widget>[
            if (goal != null)
              IconButton(
                tooltip: 'Edit savings goal'.tr,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Get.toNamed<void>(
                  AppRoutes.savingsGoalForm,
                  arguments: goal,
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: goal == null
              ? (goals.isLoading.value
                    ? const AppContent(
                        child: SkeletonList(
                          count: 3,
                          type: SkeletonType.budget,
                        ),
                      )
                    : EmptyState(
                        icon: Icons.flag_outlined,
                        title: 'This savings goal no longer exists'.tr,
                        message: '',
                      ))
              : AppContent(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await goals.load(silent: true);
                      await controller.load(silent: true);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                      children: <Widget>[
                        _Header(goal: goal),
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          label: 'Add money'.tr,
                          icon: Icons.add_rounded,
                          onPressed: () => showAddMoneySheet(context, goal),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        SectionHeader(title: 'History'.tr),
                        const SizedBox(height: AppSpacing.sm),
                        _History(controller: controller, goal: goal),
                      ],
                    ),
                  ),
                ),
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.goal});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      AppFormatters.money(goal.totalSaved),
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'of @amount'.trParams(<String, String>{
                        'amount': AppFormatters.money(goal.targetAmount),
                      }),
                      style: text.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${AppFormatters.number(goal.progress * 100, decimalDigits: 0)}%',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppProgressBar(value: goal.progress, color: color),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (goal.isReached)
                StatusPill(
                  label: 'Goal reached'.tr,
                  color: color,
                  icon: Icons.check_circle_outline,
                )
              else
                Text(
                  '@amount left'.trParams(<String, String>{
                    'amount': AppFormatters.money(goal.remaining),
                  }),
                  style: text.titleSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (overdue)
                StatusPill(
                  label: 'Overdue'.tr,
                  color: color,
                  icon: Icons.schedule_outlined,
                ),
              if (targetDate != null)
                Text(
                  'By @date'.trParams(<String, String>{
                    'date': AppFormatters.date(targetDate),
                  }),
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.controller, required this.goal});

  final SavingsGoalDetailController controller;
  final SavingsGoal goal;

  Future<void> _remove(BuildContext context, SavingsHistoryEntry entry) async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Remove this entry?'.tr,
      message: '@goal goes down by @amount.'.trParams(<String, String>{
        'goal': goal.name,
        'amount': AppFormatters.money(entry.contribution.amount),
      }),
      confirmLabel: 'Remove'.tr,
    );
    if (!confirmed) return;
    if (await controller.deleteEntry(entry.contribution.id)) {
      AppSnackbar.show('Entry removed'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Obx(() {
      if (controller.isLoading.value) {
        return const SkeletonList(count: 3, type: SkeletonType.transaction);
      }
      final String? error = controller.error.value;
      final List<SavingsHistoryEntry> entries = controller.history;
      final bool hasStart = goal.savedAmount > Decimal.zero;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (error != null) ...<Widget>[
            InlineMessage(
              message: error,
              tone: InlineMessageTone.error,
              action: TextButton(
                onPressed: controller.load,
                child: Text('Retry'.tr),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SubmitErrorMessage(controller.deletion),
          if (entries.isEmpty && !hasStart && error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'Money you add shows up here.'.tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else
            AppListCard(
              children: <Widget>[
                for (final SavingsHistoryEntry entry in entries)
                  _EntryTile(
                    entry: entry,
                    color: entry.contribution.isFromIncome
                        ? money.income
                        : colors.primary,
                    onTap: entry.contribution.isFromIncome
                        ? () => Get.toNamed<void>(
                            AppRoutes.transactionDetail,
                            arguments: entry.contribution.transactionId,
                          )
                        : () => _remove(context, entry),
                  ),
                // The starting amount is the oldest line, so it closes the
                // list once every page is shown.
                if (hasStart && !controller.hasMore.value)
                  AppListTile(
                    leading: IconBadge(
                      icon: Icons.flag_outlined,
                      color: colors.onSurfaceVariant,
                    ),
                    title: 'Starting amount'.tr,
                    subtitle: AppFormatters.date(goal.createdAt.toLocal()),
                    trailing: Text(
                      AppFormatters.money(goal.savedAmount),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          if (controller.isLoadingMore.value)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.hasMore.value)
            TextButton(
              onPressed: controller.loadMore,
              child: Text('Load more'.tr),
            ),
        ],
      );
    });
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.color,
    required this.onTap,
  });

  final SavingsHistoryEntry entry;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool fromIncome = entry.contribution.isFromIncome;
    return AppListTile(
      leading: IconBadge(
        icon: fromIncome ? Icons.south_west_rounded : Icons.savings_outlined,
        color: color,
      ),
      title: fromIncome
          ? (entry.incomeTitle ?? 'From income'.tr)
          : 'Added money'.tr,
      subtitle: fromIncome
          ? '@date · from income'.trParams(<String, String>{
              'date': AppFormatters.date(entry.date),
            })
          : '@date · tap to remove'.trParams(<String, String>{
              'date': AppFormatters.dateTime(entry.date),
            }),
      trailing: Text(
        AppFormatters.signedMoney(entry.contribution.amount, positive: true),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: onTap,
    );
  }
}
