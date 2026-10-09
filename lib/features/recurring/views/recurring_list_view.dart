import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/recurring/controllers/recurring_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void openAddRecurring() => Get.toNamed<void>(AppRoutes.recurringForm);

class RecurringListView extends GetView<RecurringController> {
  const RecurringListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Recurring'),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const AppContent(child: SkeletonList(count: 4, type: SkeletonType.generic));
          }
          final String? error = controller.error.value;
          if (error != null && controller.rules.isEmpty) {
            return LoadFailureView(message: error, onRetry: controller.load);
          }
          if (controller.rules.isEmpty) {
            return const EmptyState(
              icon: Icons.event_repeat_outlined,
              title: 'No recurring transactions',
              message:
                  'Add rent, salary, EMIs or subscriptions once and they are '
                  'recorded for you on schedule.',
              actionLabel: 'Add recurring',
              onAction: openAddRecurring,
            );
          }
          return AppContent(
            child: RefreshIndicator(
              onRefresh: () async {
                await controller.runDue();
                await controller.load();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 88),
                children: <Widget>[
                  SubmitErrorMessage(controller.toggle),
                  for (final RecurringTransaction rule in controller.rules)
                    _RuleTile(rule: rule),
                ],
              ),
            ),
          );
        }),
      ),
      floatingActionButton: const FloatingActionButton.extended(
        onPressed: openAddRecurring,
        icon: Icon(Icons.add),
        label: Text('Add recurring'),
      ),
    );
  }
}

class _RuleTile extends GetView<RecurringController> {
  const _RuleTile({required this.rule});

  final RecurringTransaction rule;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final category = controller.categoryOf(rule.categoryId);
    final bool inflow = rule.type == TransactionType.income;
    final bool ended =
        !rule.active && RecurringStatus.hasEnded(rule, DateTime.now());
    final String next = rule.active
        ? 'Next ${AppFormatters.date(rule.nextRunAt)}'
        : (ended ? 'Ended' : 'Paused');
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            Get.toNamed<void>(AppRoutes.recurringForm, arguments: rule),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(
                  CategoryIcons.of(category?.icon, rule.type),
                  size: 22,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      (rule.note ?? '').isNotEmpty
                          ? rule.note!
                          : (category?.name ?? rule.type.label),
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${rule.scheduleLabel} · $next · '
                      '${controller.accountName(rule.accountId)}',
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  MoneyText(
                    rule.amount,
                    flow: inflow ? MoneyFlow.inflow : MoneyFlow.outflow,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!ended)
                    Semantics(
                      label: rule.active ? 'Pause schedule' : 'Resume schedule',
                      child: Switch(
                        value: rule.active,
                        onChanged: (bool v) => controller.setActive(rule, v),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Presentation helper: whether a rule finished (as opposed to being paused).
abstract final class RecurringStatus {
  static bool hasEnded(RecurringTransaction r, DateTime now) =>
      r.endDate != null &&
      DateTime(
        r.endDate!.year,
        r.endDate!.month,
        r.endDate!.day,
      ).isBefore(DateTime(now.year, now.month, now.day));
}
