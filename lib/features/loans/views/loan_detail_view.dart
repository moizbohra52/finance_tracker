import 'dart:math' as math;

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
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:finance_tracker/features/loans/controllers/loan_detail_controller.dart';
import 'package:finance_tracker/features/loans/controllers/loan_form_controller.dart';
import 'package:finance_tracker/features/loans/controllers/loan_payment_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// How many instalments the schedule shows before "Show all".
const int _collapsedInstalments = 12;

void _openPayment(LoanPaymentArgs args) =>
    Get.toNamed<void>(AppRoutes.loanPaymentForm, arguments: args);

/// One loan: what is left, the next payment, the actions, the remaining EMI
/// schedule and the payments made.
class LoanDetailView extends GetView<LoanDetailController> {
  const LoanDetailView({super.key, required this.loanId});

  /// Tag of this screen's controller (see routeIdArgument).
  final String loanId;

  @override
  String get tag => loanId;

  Future<void> _delete(BuildContext context, LoanDetail detail) async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this loan?'.tr,
      message:
          'This deletes the loan, its @count payments and their transactions.'
              .trParams(<String, String>{'count': '${detail.payments.length}'}),
      confirmLabel: 'Delete'.tr,
    );
    if (!confirmed || !context.mounted) return;
    if (!await controller.deleteLoan()) return;
    Get.back<void>();
    AppSnackbar.show('Loan deleted'.tr);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final LoanDetail? detail = controller.detail.value;
      return Scaffold(
        appBar: AppAppBar(
          title: detail?.loan.name ?? 'Loan'.tr,
          actions: <Widget>[
            if (detail != null) ...<Widget>[
              IconButton(
                tooltip: 'Edit loan'.tr,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Get.toNamed<void>(
                  AppRoutes.loanForm,
                  arguments: LoanFormArgs(existing: detail.loan),
                ),
              ),
              IconButton(
                tooltip: 'Delete loan'.tr,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, detail),
              ),
            ],
          ],
        ),
        body: SafeArea(child: _body(detail)),
      );
    });
  }

  Widget _body(LoanDetail? detail) {
    if (controller.isLoading.value) {
      return const AppContent(
        child: SkeletonList(count: 4, type: SkeletonType.budget),
      );
    }
    final String? error = controller.error.value;
    if (detail == null) {
      return error != null
          ? LoadFailureView(message: error, onRetry: controller.load)
          : EmptyState(
              icon: Icons.account_balance_outlined,
              title: 'Loan not found'.tr,
              message: '',
            );
    }
    return AppContent(
      child: RefreshIndicator(
        onRefresh: () => controller.load(silent: true),
        child: _Content(controller: controller, detail: detail),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.controller, required this.detail});

  final LoanDetailController controller;
  final LoanDetail detail;

  Future<void> _deletePayment(BuildContext context, LoanPayment p) async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this payment?'.tr,
      message: 'Its transactions are removed too.'.tr,
      confirmLabel: 'Delete'.tr,
    );
    if (!confirmed) return;
    if (await controller.deletePayment(p.id)) {
      AppSnackbar.show('Payment deleted'.tr);
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() => _list(context));

  Widget _list(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<LoanInstalment> schedule = controller.schedule;
    final bool expanded = controller.scheduleExpanded.value;
    final int shown = expanded
        ? schedule.length
        : math.min(schedule.length, _collapsedInstalments);
    final List<LoanPayment> payments = detail.payments;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(
                detail: detail,
                progress: controller.progress,
                percent: controller.progressPercent,
              ),
              const SizedBox(height: AppSpacing.md),
              SubmitErrorMessage(controller.deletion),
              if (!detail.loan.isClosed) _Actions(detail: detail),
            ],
          ),
        ),
        if (schedule.isNotEmpty) ...<Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.lg,
                bottom: AppSpacing.sm,
              ),
              child: SectionHeader(title: 'Remaining EMIs'.tr),
            ),
          ),
          SliverList.separated(
            itemCount: shown,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int i) =>
                _InstalmentTile(instalment: schedule[i]),
          ),
          if (shown < schedule.length)
            SliverToBoxAdapter(
              child: TextButton(
                onPressed: () => controller.scheduleExpanded.value = true,
                child: Text(
                  'Show all (@count)'.trParams(<String, String>{
                    'count': '${schedule.length - shown}',
                  }),
                ),
              ),
            ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.lg,
              bottom: AppSpacing.sm,
            ),
            child: SectionHeader(title: 'Payments'.tr),
          ),
        ),
        if (payments.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'No payments yet'.tr,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          SliverList.separated(
            itemCount: payments.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int i) {
              final LoanPayment p = payments[i];
              return _PaymentTile(
                payment: p,
                canChange: controller.canChange(p),
                onEdit: () => _openPayment(
                  LoanPaymentArgs(
                    loanId: detail.loan.id,
                    existing: p,
                    kind: p.kind,
                  ),
                ),
                onDelete: () => _deletePayment(context, p),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.progress,
    required this.percent,
  });

  final LoanDetail detail;
  final double progress;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final Loan loan = detail.loan;
    final LoanStatus status = detail.status;
    final Color color = loan.direction == LoanDirection.taken
        ? money.payable
        : money.receivable;
    final DateTime? next = status.nextDueDate;
    final String nextText = next == null
        ? ''
        : status.nextAmount == null
        ? 'Next @date'.trParams(<String, String>{
            'date': AppFormatters.date(next),
          })
        : 'Next @date · @amount'.trParams(<String, String>{
            'date': AppFormatters.date(next),
            'amount': AppFormatters.money(status.nextAmount!),
          });
    final TextStyle? muted = text.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Outstanding'.tr, style: muted),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: CountUpMoney(
                        status.outstanding,
                        style: text.headlineSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (loan.isClosed) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                StatusPill(
                  label: 'Closed'.tr,
                  color: money.income,
                  icon: Icons.check_circle_outline,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppProgressBar(value: progress, color: color),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '@percent% repaid · loan amount @amount'.trParams(<String, String>{
              'percent': AppFormatters.number(percent, decimalDigits: 0),
              'amount': AppFormatters.money(loan.principal),
            }),
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (nextText.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              nextText,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: Text('Interest paid so far'.tr, style: muted)),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  AppFormatters.money(status.interestPaid),
                  textAlign: TextAlign.end,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.detail});

  final LoanDetail detail;

  @override
  Widget build(BuildContext context) {
    final String id = detail.loan.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppButton(
          label: 'Record payment'.tr,
          icon: Icons.add_rounded,
          onPressed: () => _openPayment(LoanPaymentArgs(loanId: id)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            if (detail.loan.method == LoanMethod.emi) ...<Widget>[
              Expanded(
                child: AppButton(
                  label: 'Prepay'.tr,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _openPayment(
                    LoanPaymentArgs(loanId: id, kind: LoanPaymentKind.extra),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: AppButton(
                label: 'Close loan'.tr,
                variant: AppButtonVariant.secondary,
                onPressed: () =>
                    _openPayment(LoanPaymentArgs(loanId: id, closing: true)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InstalmentTile extends StatelessWidget {
  const _InstalmentTile({required this.instalment});

  final LoanInstalment instalment;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      padding: AppListTile.flatPadding,
      leading: IconBadge(
        icon: Icons.event_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: 'EMI @number · @date'.trParams(<String, String>{
        'number': '${instalment.number}',
        'date': AppFormatters.date(instalment.dueDate),
      }),
      subtitle: 'Principal @principal · Interest @interest'
          .trParams(<String, String>{
            'principal': AppFormatters.money(instalment.principal),
            'interest': AppFormatters.money(instalment.interest),
          }),
      subtitleMaxLines: 2,
      trailing: Text(
        AppFormatters.money(instalment.amount),
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.payment,
    required this.canChange,
    required this.onEdit,
    required this.onDelete,
  });

  final LoanPayment payment;
  final bool canChange;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String date = AppFormatters.date(payment.paidAt);
    final FinanceColors money = FinanceColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppListTile(
          padding: AppListTile.flatPadding,
          leading: IconBadge(
            icon: Icons.payments_outlined,
            color: money.income,
          ),
          title: payment.kind == LoanPaymentKind.extra
              ? 'Prepayment · @date'.trParams(<String, String>{'date': date})
              : date,
          subtitle: 'Principal @principal · Interest @interest'
              .trParams(<String, String>{
                'principal': AppFormatters.money(payment.principalPart),
                'interest': AppFormatters.money(payment.interestPart),
              }),
          subtitleMaxLines: 2,
          trailing: Text(
            AppFormatters.money(payment.amount),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (canChange)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text('Edit'.tr),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text('Delete'.tr),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
