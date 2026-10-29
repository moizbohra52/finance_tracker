import 'package:decimal/decimal.dart';
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
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/features/split/controllers/split_group_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The groups list. A row opens the group detail (Task 11).
class SplitGroupListView extends GetView<SplitGroupController> {
  const SplitGroupListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: 'Split groups'.tr),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const AppContent(
              child: SkeletonList(count: 4, type: SkeletonType.budget),
            );
          }
          final String? error = controller.error.value;
          if (error != null && controller.groups.isEmpty) {
            return LoadFailureView(message: error, onRetry: controller.load);
          }
          if (controller.groups.isEmpty) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: 'No groups yet'.tr,
              message: 'Make one for a trip, flatmates or office lunch'.tr,
              actionLabel: 'New group'.tr,
              onAction: () => openSplitGroupForm(),
            );
          }
          return AppContent(
            child: RefreshIndicator(
              onRefresh: controller.load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: controller.groups.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (BuildContext context, int index) =>
                    _GroupCard(summary: controller.groups[index]),
              ),
            ),
          );
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openSplitGroupForm(),
        icon: const Icon(Icons.add),
        label: Text('New group'.tr),
      ),
    );
  }
}

/// Opens the group form; [existing] edits an existing group.
void openSplitGroupForm([SplitGroupSummary? existing]) =>
    Get.toNamed<void>(AppRoutes.splitGroupForm, arguments: existing);

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.summary});

  final SplitGroupSummary summary;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final Decimal net = summary.userNet;
    final String netText = net > Decimal.zero
        ? 'You get @amount'.trParams(<String, String>{
            'amount': AppFormatters.money(net),
          })
        : net < Decimal.zero
        ? 'You owe @amount'.trParams(<String, String>{
            'amount': AppFormatters.money(-net),
          })
        : 'Settled'.tr;
    final Color netColor = net > Decimal.zero
        ? money.receivable
        : net < Decimal.zero
        ? money.payable
        : colors.onSurfaceVariant;

    return AppCard(
      onTap: () => Get.toNamed<void>(
        AppRoutes.splitGroupDetail,
        arguments: summary.group.id,
      ),
      child: Row(
        children: <Widget>[
          IconBadge(icon: Icons.groups_outlined, color: colors.primary),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  summary.group.name,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '@count members'.trParams(<String, String>{
                    'count': '${summary.memberCount}',
                  }),
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            netText,
            style: text.titleSmall?.copyWith(
              color: netColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
