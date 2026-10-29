import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_balances.dart';
import 'package:finance_tracker/features/split/controllers/split_expense_controller.dart';
import 'package:finance_tracker/features/split/controllers/split_group_detail_controller.dart';
import 'package:finance_tracker/features/split/views/split_group_list_view.dart'
    show openSplitGroupForm;
import 'package:finance_tracker/features/split/views/split_settlement_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// One group's detail: header, balances and the paged activity feed.
class SplitGroupDetailView extends GetView<SplitGroupDetailController> {
  const SplitGroupDetailView({super.key, required this.groupId});

  /// Tag of this screen's controller (see routeIdArgument).
  final String groupId;

  @override
  String get tag => groupId;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        appBar: AppAppBar(
          title: controller.detail.value?.group.name ?? '',
          actions: <Widget>[
            IconButton(
              tooltip: 'Edit group'.tr,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () async {
                final SplitGroupDetail? detail = controller.detail.value;
                if (detail == null) return;
                String meId = '';
                for (final SplitMember m in detail.members) {
                  if (m.isMe) meId = m.id;
                }
                final SplitGroupSummary summary = SplitGroupSummary(
                  group: detail.group,
                  memberCount: detail.members.length,
                  userNet: detail.balances.netOf(meId),
                );
                openSplitGroupForm(summary);
                await controller.load();
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Obx(() {
            if (controller.isLoading.value) {
              return const AppContent(
                child: SkeletonList(count: 5, type: SkeletonType.budget),
              );
            }
            final String? error = controller.error.value;
            final SplitGroupDetail? detail = controller.detail.value;
            if (error != null && detail == null) {
              return LoadFailureView(message: error, onRetry: controller.load);
            }
            if (detail == null) return const SizedBox.shrink();
            return RefreshIndicator(
              onRefresh: controller.load,
              child: _ActivityList(controller: controller, detail: detail),
            );
          }),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Get.toNamed<void>(
            AppRoutes.splitExpenseForm,
            arguments: SplitExpenseArgs(groupId: controller.groupId),
          ),
          icon: const Icon(Icons.add),
          label: Text('Add expense'.tr),
        ),
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.controller, required this.detail});

  final SplitGroupDetailController controller;
  final SplitGroupDetail detail;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String meId = detail.members.firstWhere((SplitMember m) => m.isMe).id;
    final Decimal net = detail.balances.netOf(meId);
    final String netText = net > Decimal.zero
        ? 'You get @amount'.trParams(<String, String>{
            'amount': AppFormatters.money(net),
          })
        : net < Decimal.zero
        ? 'You owe @amount'.trParams(<String, String>{
            'amount': AppFormatters.money(-net),
          })
        : 'Settled'.tr;

    return AppContent(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _HeaderTile(
                  label: 'Total spent'.tr,
                  value: AppFormatters.money(detail.totalSpent),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _HeaderTile(
                  label: 'Your share'.tr,
                  value: AppFormatters.money(detail.userShareTotal),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _HeaderTile(label: 'Balance'.tr, value: netText),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Balances'.tr, style: text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          if (detail.balances.pairs.isEmpty)
            Text(
              'Settled'.tr,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final PairBalance pair in detail.balances.pairs)
              _BalanceRow(controller: controller, pair: pair),
          const SizedBox(height: AppSpacing.lg),
          Text('Activity'.tr, style: text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          if (controller.activity.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: Text('No expenses yet'.tr)),
            )
          else
            Obx(
              () => Column(
                children: <Widget>[
                  for (final SplitActivityItem item in controller.activity)
                    _ActivityRow(controller: controller, item: item),
                  if (controller.isLoadingMore.value)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: CircularProgressIndicator(),
                    )
                  else if (controller.hasMore.value)
                    TextButton(
                      onPressed: controller.loadMore,
                      child: Text('Load more'.tr),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderTile extends StatelessWidget {
  const _HeaderTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            child: Text(
              value,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.controller, required this.pair});

  final SplitGroupDetailController controller;
  final PairBalance pair;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final FinanceColors money = FinanceColors.of(context);
    final String from = controller.memberNameById(pair.debtorMemberId);
    final String to = controller.memberNameById(pair.creditorMemberId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '@from → @to @amount'.trParams(<String, String>{
                'from': from,
                'to': to,
                'amount': AppFormatters.money(pair.amount),
              }),
              style: text.bodyMedium,
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => Get.toNamed<void>(
              AppRoutes.splitSettlementForm,
              arguments: SplitSettlementArgs(
                groupId: controller.groupId,
                fromMemberId: pair.debtorMemberId,
                toMemberId: pair.creditorMemberId,
              ),
            ),
            child: Text('Settle'.tr),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            AppFormatters.money(pair.amount),
            style: text.titleSmall?.copyWith(
              color: money.payable,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.controller, required this.item});

  final SplitGroupDetailController controller;
  final SplitActivityItem item;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget row = switch (item) {
      SplitActivityExpense(
        :final SplitExpense expense,
        :final SplitPart? userPart,
      ) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(
            expense.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            userPart == null
                ? AppFormatters.money(expense.totalAmount)
                : 'Your share @amount'.trParams(<String, String>{
                    'amount': AppFormatters.money(userPart.shareAmount),
                  }),
          ),
          trailing: Text(
            AppFormatters.money(expense.totalAmount),
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          onTap: () async {
            final SplitExpenseDetail existing;
            try {
              existing = await controller.expenseDetail(expense.id);
            } on AppException {
              return; // The feed reloads on the notifier; the tap just waits.
            }
            await Get.toNamed<void>(
              AppRoutes.splitExpenseForm,
              arguments: SplitExpenseArgs(
                groupId: expense.groupId,
                existing: existing,
              ),
            );
          },
        ),
      SplitActivitySettlement(:final SplitSettlement settlement) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.handshake_outlined),
        title: Text(
          '@from paid @to'.trParams(<String, String>{
            'from': controller.memberNameById(settlement.fromMemberId),
            'to': controller.memberNameById(settlement.toMemberId),
          }),
        ),
        trailing: Text(
          AppFormatters.money(settlement.amount),
          style: text.titleSmall?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        onTap: () => Get.toNamed<void>(
          AppRoutes.splitSettlementForm,
          arguments: SplitSettlementArgs(
            groupId: settlement.groupId,
            existing: settlement,
          ),
        ),
      ),
    };
    return row;
  }
}
