import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/chart_palette.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/category_breakdown.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/report_calculator.dart';
import 'package:finance_tracker/features/budgets/views/budget_list_view.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/features/contacts/views/contact_picker_sheet.dart';
import 'package:finance_tracker/features/dashboard/controllers/home_controller.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Home tab: balance first, then quick actions, khata and recent activity.
class DashboardView extends GetView<HomeController> {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const AppContent(child: SkeletonList());
      }
      final String? error = controller.error.value;
      if (error != null && controller.accounts.isEmpty) {
        return LoadFailureView(message: error, onRetry: controller.load);
      }
      return RefreshIndicator(
        onRefresh: controller.load,
        child: AppContent(
          maxWidth: AppSizes.maxPageWidth,
          child: ListView(
            children: <Widget>[
              const _GreetingHeader(),
              const SizedBox(height: AppSpacing.md),
              if (error != null) ...<Widget>[
                _RefreshFailedBanner(message: error),
                const SizedBox(height: AppSpacing.md),
              ],
              if (controller.accounts.isEmpty)
                const _NoAccountsCard()
              else ...<Widget>[
                const _BalanceSection(),
                const SizedBox(height: AppSpacing.lg),
                const _QuickActions(),
                const SizedBox(height: AppSpacing.lg),
                const _TodaySummary(),
                const SizedBox(height: AppSpacing.lg),
                const _MonthlySummary(),
                const SizedBox(height: AppSpacing.lg),
                const _SpendingOverview(),
                const SizedBox(height: AppSpacing.lg),
                const _KhataSummary(),
                const SizedBox(height: AppSpacing.lg),
                const _PlanSection(),
                const SizedBox(height: AppSpacing.lg),
                const _AccountsSection(),
                const SizedBox(height: AppSpacing.lg),
                const _RecentTransactions(),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      );
    });
  }
}

/// Greeting and avatar. The avatar opens the profile.
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  static String _greeting(DateTime now) => now.hour < 12
      ? 'Good morning'
      : (now.hour < 17 ? 'Good afternoon' : 'Good evening');

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ProfileController profile = Get.find<ProfileController>();
    return Obx(() {
      final String name = profile.displayName.value.trim();
      final String first = name.isEmpty ? '' : name.split(' ').first;
      return Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_greeting(DateTime.now()), style: text.bodyMedium),
                Text(
                  first.isEmpty ? 'Welcome back' : first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Open profile',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Get.toNamed<void>(AppRoutes.profile),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: Text(first.isEmpty ? '?' : first[0].toUpperCase()),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _BalanceSection extends GetView<HomeController> {
  const _BalanceSection();

  @override
  Widget build(BuildContext context) => Obx(
    () => BalanceCard(
      currentBalance: controller.currentBalance.value,
      openingBalance: controller.openingBalance.value,
      monthIncome: controller.month.value.income,
      monthExpense: controller.month.value.expense,
      isHidden: controller.balanceHidden.value,
      onToggleHidden: controller.toggleBalanceHidden,
    ),
  );
}

class _MonthlySummary extends GetView<HomeController> {
  const _MonthlySummary();

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'This month',
          actionLabel: 'Reports',
          onAction: () => Get.toNamed<void>(AppRoutes.reports),
        ),
        Obx(() {
          final PeriodSummary m = controller.month.value;
          final bool positive = m.net >= Decimal.zero;
          return AppCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _Figure(
                    label: 'Income',
                    value: AppFormatters.money(m.income),
                    color: money.income,
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Expense',
                    value: AppFormatters.money(m.expense),
                    color: money.expense,
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Net',
                    value: AppFormatters.signedMoney(m.net, positive: positive),
                    color: positive ? money.income : money.expense,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Transfers are not counted as income or expense.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        Text(label, style: text.labelMedium),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: text.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Top expense categories this month.
class _SpendingOverview extends GetView<HomeController> {
  const _SpendingOverview();

  static const int _maxRows = 4;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Spending overview',
          actionLabel: 'Details',
          onAction: () => Get.toNamed<void>(AppRoutes.reports),
        ),
        Obx(() {
          final List<CategoryTotal> top = controller.monthCategories
              .take(_maxRows)
              .toList();
          if (top.isEmpty) {
            return const AppCard(child: Text('No expenses this month yet.'));
          }
          return AppCard(
            child: CategoryBreakdown(
              rows: <BreakdownRow>[
                for (int i = 0; i < top.length; i++)
                  BreakdownRow(
                    label:
                        controller.categoryOf(top[i].categoryId)?.name ??
                        'Uncategorised',
                    icon: CategoryIcons.of(
                      controller.categoryOf(top[i].categoryId)?.icon,
                      TransactionType.expense,
                    ),
                    amount: AppFormatters.money(top[i].amount),
                    share: top[i].share,
                    color: ChartPalette.at(context, i),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Entry points to budgets and recurring schedules.
class _PlanSection extends StatelessWidget {
  const _PlanSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Plan ahead'),
        Row(
          children: <Widget>[
            Expanded(
              child: PlanTile(
                icon: Icons.savings_outlined,
                title: 'Budgets',
                subtitle: 'Set limits and track what is left',
                onTap: () => Get.toNamed<void>(AppRoutes.budgets),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PlanTile(
                icon: Icons.event_repeat_outlined,
                title: 'Recurring',
                subtitle: 'Rent, salary, EMIs on autopilot',
                onTap: () => Get.toNamed<void>(AppRoutes.recurring),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RefreshFailedBanner extends StatelessWidget {
  const _RefreshFailedBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        '$message Pull down to retry.',
        style: TextStyle(color: colors.onErrorContainer),
      ),
    );
  }
}

class _NoAccountsCard extends StatelessWidget {
  const _NoAccountsCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Add your first account',
        message:
            'Create a cash, bank or UPI account with its opening balance. '
            'Then you can record income and expenses.',
        actionLabel: 'Add account',
        onAction: () => Get.toNamed<void>(AppRoutes.accountForm),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  void _addTransaction(TransactionType type) => Get.toNamed<void>(
    AppRoutes.transactionForm,
    arguments: TransactionFormArgs(type: type),
  );

  Future<void> _addEntry(ContactTransactionType type) async {
    final Contact? contact = await pickContact();
    if (contact == null) return;
    await Get.toNamed<void>(
      AppRoutes.contactEntry,
      arguments: ContactEntryArgs(
        contactId: contact.id,
        contactName: contact.name,
        type: type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        QuickActionButton(
          icon: Icons.south_west_rounded,
          label: 'Income',
          onTap: () => _addTransaction(TransactionType.income),
        ),
        QuickActionButton(
          icon: Icons.north_east_rounded,
          label: 'Expense',
          onTap: () => _addTransaction(TransactionType.expense),
        ),
        QuickActionButton(
          icon: Icons.add_card_outlined,
          label: 'Credit',
          onTap: () => _addEntry(ContactTransactionType.credit),
        ),
        QuickActionButton(
          icon: Icons.remove_circle_outline,
          label: 'Debit',
          onTap: () => _addEntry(ContactTransactionType.debit),
        ),
        QuickActionButton(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Accounts',
          onTap: () => Get.toNamed<void>(AppRoutes.accounts),
        ),
      ],
    );
  }
}

class _TodaySummary extends GetView<HomeController> {
  const _TodaySummary();

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    return Obx(() {
      final bool hidden = controller.balanceHidden.value;
      String show(Object v) => hidden ? '••••' : v.toString();
      return Row(
        children: <Widget>[
          Expanded(
            child: SummaryTile(
              icon: Icons.south_west_rounded,
              label: "Today's income",
              value: show(AppFormatters.money(controller.today.value.income)),
              color: money.income,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: SummaryTile(
              icon: Icons.north_east_rounded,
              label: "Today's expense",
              value: show(AppFormatters.money(controller.today.value.expense)),
              color: money.expense,
            ),
          ),
        ],
      );
    });
  }
}

class _KhataSummary extends GetView<HomeController> {
  const _KhataSummary();

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Khata',
          actionLabel: 'Open',
          onAction: () => Get.toNamed<void>(AppRoutes.contacts),
        ),
        Obx(() {
          if (controller.contactCount.value == 0) {
            return AppCard(
              child: Row(
                children: <Widget>[
                  const Icon(Icons.people_outline),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(
                    child: Text(
                      'Track who owes you and who you owe. Add your first '
                      'contact.',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Get.toNamed<void>(AppRoutes.contactForm),
                    child: const Text('Add'),
                  ),
                ],
              ),
            );
          }
          return Row(
            children: <Widget>[
              Expanded(
                child: SummaryTile(
                  icon: Icons.call_received_rounded,
                  label: 'You will get',
                  value: AppFormatters.money(controller.khata.value.receivable),
                  color: money.receivable,
                  onTap: () => Get.toNamed<void>(AppRoutes.contacts),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SummaryTile(
                  icon: Icons.call_made_rounded,
                  label: 'You will give',
                  value: AppFormatters.money(controller.khata.value.payable),
                  color: money.payable,
                  onTap: () => Get.toNamed<void>(AppRoutes.contacts),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

class _AccountsSection extends GetView<HomeController> {
  const _AccountsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Accounts',
          actionLabel: 'Manage',
          onAction: () => Get.toNamed<void>(AppRoutes.accounts),
        ),
        Obx(
          () => AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: <Widget>[
                for (final Account a in controller.accounts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_accountIcon(a.type)),
                    title: Text(a.name),
                    subtitle: Text(a.type.name.toUpperCase()),
                    trailing: Text(
                      controller.balanceHidden.value
                          ? '••••'
                          : AppFormatters.money(
                              controller.balances[a.id] ?? a.openingBalance,
                            ),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    onTap: () => Get.toNamed<void>(
                      AppRoutes.accountDetail,
                      arguments: a.id,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

IconData _accountIcon(AccountType type) => switch (type) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.bank => Icons.account_balance_outlined,
  AccountType.upi => Icons.qr_code_2_rounded,
  AccountType.card => Icons.credit_card_outlined,
  AccountType.other => Icons.wallet_outlined,
};

class _RecentTransactions extends GetView<HomeController> {
  const _RecentTransactions();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Recent transactions',
          actionLabel: 'See all',
          onAction: () => Get.toNamed<void>(AppRoutes.transactions),
        ),
        Obx(() {
          if (controller.recent.isEmpty) {
            return AppCard(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions yet',
                message: 'Record your first income or expense to see it here.',
                actionLabel: 'Add expense',
                onAction: () => Get.toNamed<void>(
                  AppRoutes.transactionForm,
                  arguments: const TransactionFormArgs(),
                ),
              ),
            );
          }
          return AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              children: <Widget>[
                for (final Transaction t in controller.recent)
                  TransactionListItem(
                    transaction: t,
                    title:
                        controller.categoryOf(t.categoryId)?.name ??
                        t.type.name,
                    iconKey: controller.categoryOf(t.categoryId)?.icon,
                    subtitle: controller.accountName(t.accountId),
                    onTap: () => Get.toNamed<void>(
                      AppRoutes.transactionDetail,
                      arguments: t.id,
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
