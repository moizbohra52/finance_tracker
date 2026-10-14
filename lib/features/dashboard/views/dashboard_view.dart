import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/chart_palette.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/category_breakdown.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
import 'package:finance_tracker/domain/services/report_calculator.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/features/contacts/views/contact_picker_sheet.dart';
import 'package:finance_tracker/features/dashboard/controllers/home_controller.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/account_list_item.dart';
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
                InlineMessage(message: '$error Pull down to retry.'),
                const SizedBox(height: AppSpacing.md),
              ],
              if (controller.accounts.isEmpty)
                const _NoAccountsCard()
              else ...<Widget>[
                // Order follows docs/06: balance, income/expense, khata,
                // recent activity, then planning and breakdowns.
                const _BalanceSection(),
                const SizedBox(height: AppSpacing.md),
                const _QuickActions(),
                const SizedBox(height: AppSpacing.lg),
                const _TodaySummary(),
                const SizedBox(height: AppSpacing.lg),
                const _MonthlySummary(),
                const SizedBox(height: AppSpacing.lg),
                const _KhataSummary(),
                const SizedBox(height: AppSpacing.lg),
                const _RecentTransactions(),
                const SizedBox(height: AppSpacing.lg),
                const _SpendingOverview(),
                const SizedBox(height: AppSpacing.lg),
                const _PlanSection(),
                const SizedBox(height: AppSpacing.lg),
                const _AccountsSection(),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      );
    });
  }
}

/// Greeting and inspirational finance quote.
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  static ({String text, IconData icon}) _greeting(DateTime now) {
    if (now.hour < 12) {
      return (text: 'Good morning', icon: Icons.wb_sunny_rounded);
    } else if (now.hour < 17) {
      return (text: 'Good afternoon', icon: Icons.wb_twilight_rounded);
    } else {
      return (text: 'Good evening', icon: Icons.nights_stay_rounded);
    }
  }

  static const List<({String quote, String author})> _quotes = [
    (
      quote:
          'Do not save what is left after spending, but spend what is left after saving.',
      author: 'Warren Buffett',
    ),
    (
      quote: 'Beware of little expenses. A small leak will sink a great ship.',
      author: 'Benjamin Franklin',
    ),
    (
      quote:
          'A budget is telling your money where to go instead of wondering where it went.',
      author: 'Dave Ramsey',
    ),
    (
      quote:
          'Financial freedom is available to those who learn about it and work for it.',
      author: 'Robert Kiyosaki',
    ),
    (
      quote:
          'The secret of getting ahead is getting started. Track your daily expenses.',
      author: 'Mark Twain',
    ),
    (
      quote: 'Small daily savings compound into monumental financial security.',
      author: 'Financial Wisdom',
    ),
    (
      quote: 'Never spend your money before you have earned it.',
      author: 'Thomas Jefferson',
    ),
    (
      quote: 'The art is not in making money, but in keeping it.',
      author: 'Proverb',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    final DateTime now = DateTime.now();
    final greeting = _greeting(now);
    final int quoteIndex = (now.day + now.month) % _quotes.length;
    final dailyQuote = _quotes[quoteIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                greeting.text,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(greeting.icon, size: 22, color: colors.primary),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '“${dailyQuote.quote}” — ${dailyQuote.author}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            height: 1.35,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
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
    final ColorScheme colors = Theme.of(context).colorScheme;
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
          // Same privacy rule as the balance card above it.
          final bool hidden = controller.balanceHidden.value;
          String show(String value) => hidden ? '••••' : value;
          return AppCard(
            child: IntrinsicHeight(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _Figure(
                      label: 'Income',
                      value: show(AppFormatters.money(m.income)),
                      color: money.income,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    indent: 4,
                    endIndent: 4,
                    color: colors.outlineVariant.withValues(alpha: 0.35),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Expense',
                      value: show(AppFormatters.money(m.expense)),
                      color: money.expense,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    indent: 4,
                    endIndent: 4,
                    color: colors.outlineVariant.withValues(alpha: 0.35),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Net',
                      value: show(
                        AppFormatters.signedMoney(m.net, positive: positive),
                      ),
                      color: positive ? money.income : money.expense,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Transfers are not counted as income or expense.',
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Text(
          label,
          style: text.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: text.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
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
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: PlanTile(
                icon: Icons.notifications_active_outlined,
                title: 'Reminders',
                subtitle: 'Never miss a payment or a due date',
                onTap: () => Get.toNamed<void>(AppRoutes.reminders),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PlanTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Alerts and reminders you received',
                onTap: () => Get.toNamed<void>(AppRoutes.notifications),
              ),
            ),
          ],
        ),
      ],
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
    final List<QuickActionButton> actions = <QuickActionButton>[
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
      // Accounts stay one tap away in the Accounts section below.
      QuickActionButton(
        icon: Icons.swap_horiz_rounded,
        label: 'Transfer',
        onTap: () => Get.toNamed<void>(AppRoutes.transferForm),
      ),
    ];
    // Equal cells, so five actions fit a narrow phone; a long label is
    // shortened rather than pushing the row off screen.
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          for (final QuickActionButton action in actions)
            Expanded(child: action),
        ],
      ),
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
              padding: EdgeInsets.zero,
              child: AppListTile(
                leading: const IconBadge(icon: Icons.people_outline),
                title: 'No contacts yet',
                subtitle:
                    'Track who owes you and who you owe. Add your first '
                    'contact.',
                subtitleMaxLines: 3,
                trailing: TextButton(
                  onPressed: () => Get.toNamed<void>(AppRoutes.contactForm),
                  child: const Text('Add'),
                ),
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
          () => AppListCard(
            children: <Widget>[
              for (final Account a in controller.accounts)
                AccountTile(
                  account: a,
                  balance: controller.balances[a.id] ?? a.openingBalance,
                  isHidden: controller.balanceHidden.value,
                  onTap: () => Get.toNamed<void>(
                    AppRoutes.accountDetail,
                    arguments: a.id,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

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
          return AppListCard(
            children: <Widget>[
              for (final Transaction t in controller.recent)
                TransactionListItem(
                  transaction: t,
                  title: TransactionListItem.titleFor(
                    t,
                    categoryName: controller.categoryOf(t.categoryId)?.name,
                    nearby: controller.recent,
                    accountName: controller.accountName,
                  ),
                  iconKey: controller.categoryOf(t.categoryId)?.icon,
                  subtitle: controller.accountName(t.accountId),
                  onTap: () => Get.toNamed<void>(
                    AppRoutes.transactionDetail,
                    arguments: t.id,
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}
