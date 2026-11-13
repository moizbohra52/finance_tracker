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
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/features/loans/controllers/loan_form_controller.dart';
import 'package:finance_tracker/features/loans/controllers/loan_list_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Opens the loan form for a new loan in [direction].
void openAddLoan(LoanDirection direction) => Get.toNamed<void>(
  AppRoutes.loanForm,
  arguments: LoanFormArgs(direction: direction),
);

/// Loans taken and given: the total owed, open loans with their progress and
/// next payment, and a collapsed section of closed ones.
class LoanListView extends GetView<LoanListController> {
  const LoanListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: 'Loans'.tr),
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const AppContent(
              child: SkeletonList(count: 4, type: SkeletonType.budget),
            );
          }
          final String? error = controller.error.value;
          if (error != null && controller.loans.isEmpty) {
            return LoadFailureView(message: error, onRetry: controller.load);
          }
          if (controller.loans.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_outlined,
              title: 'No loans yet'.tr,
              message:
                  'Track a loan you took or gave: the EMI, what is left and when the next payment is due.'
                      .tr,
              actionLabel: 'Add loan'.tr,
              onAction: () => openAddLoan(controller.direction.value),
            );
          }
          return AppContent(
            child: RefreshIndicator(
              onRefresh: () => controller.load(silent: true),
              child: _LoanList(controller: controller),
            ),
          );
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openAddLoan(controller.direction.value),
        icon: const Icon(Icons.add),
        label: Text('Add loan'.tr),
      ),
    );
  }
}

class _LoanList extends StatelessWidget {
  const _LoanList({required this.controller});

  final LoanListController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Obx(() {
      final bool taken = controller.direction.value == LoanDirection.taken;
      final List<LoanSummary> open = controller.open;
      final List<LoanSummary> closed = controller.closed;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.fabClearance),
        children: <Widget>[
          SegmentedButton<LoanDirection>(
            segments: <ButtonSegment<LoanDirection>>[
              ButtonSegment<LoanDirection>(
                value: LoanDirection.taken,
                label: Text('Taken'.tr),
              ),
              ButtonSegment<LoanDirection>(
                value: LoanDirection.given,
                label: Text('Given'.tr),
              ),
            ],
            selected: <LoanDirection>{controller.direction.value},
            onSelectionChanged: (Set<LoanDirection> s) =>
                controller.direction.value = s.first,
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  taken ? 'Total you owe'.tr : 'Total owed to you'.tr,
                  style: text.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppFormatters.money(controller.totalOutstanding),
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                taken ? 'No open loans taken'.tr : 'No open loans given'.tr,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          for (final LoanSummary s in open) ...<Widget>[
            _LoanCard(
              summary: s,
              progress: controller.progressOf(s),
              taken: taken,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (closed.isNotEmpty)
            ExpansionTile(
              key: const ValueKey<String>('closed-loans'),
              title: Text(
                'Closed (@count)'.trParams(<String, String>{
                  'count': '${closed.length}',
                }),
              ),
              children: <Widget>[
                for (final LoanSummary s in closed) ...<Widget>[
                  _LoanCard(
                    summary: s,
                    progress: controller.progressOf(s),
                    taken: taken,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
        ],
      );
    });
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.summary,
    required this.progress,
    required this.taken,
  });

  final LoanSummary summary;
  final double progress;
  final bool taken;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final Color color = taken ? money.payable : money.receivable;
    final Loan loan = summary.loan;
    final DateTime? next = summary.status.nextDueDate;
    final String dueText = next == null
        ? ''
        : summary.status.nextAmount == null
        ? 'Next @date'.trParams(<String, String>{
            'date': AppFormatters.date(next),
          })
        : 'Next @date · @amount'.trParams(<String, String>{
            'date': AppFormatters.date(next),
            'amount': AppFormatters.money(summary.status.nextAmount!),
          });

    return AppCard(
      onTap: () => Get.toNamed<void>(AppRoutes.loanDetail, arguments: loan.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(icon: Icons.account_balance_outlined, color: color),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: Text(
                  loan.name,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                AppFormatters.money(summary.status.outstanding),
                style: text.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppProgressBar(value: progress, color: color),
          if (dueText.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              dueText,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
