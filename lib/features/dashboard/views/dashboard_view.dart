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
                InlineMessage(
                  message: '@error Pull down to retry.'.trParams(
                    <String, String>{'error': error},
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (controller.accounts.isEmpty)
                const _NoAccountsCard()
              else ...<Widget>[
                // Order follows docs/06: balance, income/expense, pulse, khata,
                // recent activity, then planning and breakdowns.
                const _BalanceSection(),
                const SizedBox(height: AppSpacing.md),
                const _QuickActions(),
                const SizedBox(height: AppSpacing.xl),
                const _FinancialPulseCard(),
                const SizedBox(height: AppSpacing.xl),
                const _TodaySummary(),
                const SizedBox(height: AppSpacing.xl),
                const _MonthlySummary(),
                const SizedBox(height: AppSpacing.xl),
                const _KhataSummary(),
                const SizedBox(height: AppSpacing.xl),
                const _RecentTransactions(),
                const SizedBox(height: AppSpacing.xl),
                const _SpendingOverview(),
                const SizedBox(height: AppSpacing.xl),
                const _PlanSection(),
                const SizedBox(height: AppSpacing.xl),
                const _AccountsSection(),
              ],
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      );
    });
  }
}

DateTimeRange _todayRange() {
  final DateTime now = DateTime.now();
  final DateTime start = DateTime(now.year, now.month, now.day);
  final DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  return DateTimeRange(start: start, end: end);
}

DateTimeRange _monthRange() {
  final DateTime now = DateTime.now();
  final DateTime start = DateTime(now.year, now.month, 1);
  final DateTime end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  return DateTimeRange(start: start, end: end);
}

void _openTransactionsFiltered({
  TransactionType? type,
  String? categoryId,
  String? accountId,
  DateTimeRange? range,
}) {
  try {
    Get.find<TransactionController>().applyFilters(
      type: type,
      categoryId: categoryId,
      accountId: accountId,
      range: range,
    );
  } catch (_) {}
  Get.toNamed<void>(AppRoutes.transactions);
}

/// Greeting, live date, quick shortcuts and inspirational finance quote.
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  static ({String text, IconData icon}) _greeting(DateTime now) {
    if (now.hour < 12) {
      return (text: 'Good morning'.tr, icon: Icons.wb_sunny_rounded);
    } else if (now.hour < 17) {
      return (text: 'Good afternoon'.tr, icon: Icons.wb_twilight_rounded);
    } else {
      return (text: 'Good evening'.tr, icon: Icons.nights_stay_rounded);
    }
  }

  /// "Wed, 21 Oct", with day and month names in the app's language.
  static String _formatDate(DateTime now) =>
      AppFormatters.date(now, pattern: 'EEE, d MMM');

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
    final String dateString = _formatDate(now);
    final int quoteIndex = (now.day + now.month) % _quotes.length;
    final dailyQuote = _quotes[quoteIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  greeting.text,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(greeting.icon, size: 20, color: colors.primary),
              ],
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openTransactionsFiltered(range: _todayRange()),
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateString,
                        style: text.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Get.toNamed<void>(AppRoutes.reports),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border(
                  left: BorderSide(
                    color: colors.primary.withValues(alpha: 0.8),
                    width: 3.5,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.format_quote_rounded,
                    size: 16,
                    color: colors.primary.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '“${dailyQuote.quote.tr}” — ${dailyQuote.author.tr}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Monthly financial pulse showing pacing, days progress and savings rate.
class _FinancialPulseCard extends GetView<HomeController> {
  const _FinancialPulseCard();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final DateTime now = DateTime.now();
    final int daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final int daysRemaining = daysInMonth - now.day;
    final double monthProgress = (now.day / daysInMonth).clamp(0.0, 1.0);

    return Obx(() {
      final PeriodSummary m = controller.month.value;
      final bool hasActivity =
          m.income > Decimal.zero || m.expense > Decimal.zero;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Get.toNamed<void>(AppRoutes.budgets),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? <Color>[
                        colors.surfaceContainer,
                        colors.surfaceContainerHigh,
                      ]
                    : <Color>[colors.surface, colors.surfaceContainerLowest],
              ),
              border: Border.all(
                color: colors.outlineVariant.withValues(
                  alpha: isDark ? 0.3 : 0.45,
                ),
                width: 1,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: colors.shadow.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.insights_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Monthly Pace'.tr,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        '@days days left'.trParams(<String, String>{
                          'days': '$daysRemaining',
                        }),
                        style: text.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: LinearProgressIndicator(
                    value: monthProgress,
                    minHeight: 6,
                    backgroundColor: colors.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        hasActivity
                            ? (m.net >= Decimal.zero
                                  ? '🟢 On track: @amount net saved this month'
                                        .trParams(<String, String>{
                                          'amount': AppFormatters.money(m.net),
                                        })
                                  : '⚠️ Spent @amount across the month'
                                        .trParams(<String, String>{
                                          'amount': AppFormatters.money(
                                            m.expense,
                                          ),
                                        }))
                            : '💡 Day @day of @total: Track expenses daily to stay in control'
                                  .trParams(<String, String>{
                                    'day': '${now.day}',
                                    'total': '$daysInMonth',
                                  }),
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                      ),
                      onPressed: () => Get.toNamed<void>(AppRoutes.budgets),
                      child: Text('Budgets →'.tr),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
      onTap: () => Get.toNamed<void>(AppRoutes.accounts),
      onOpeningBalanceTap: () => Get.toNamed<void>(AppRoutes.accounts),
      onIncomeTap: () => _openTransactionsFiltered(
        type: TransactionType.income,
        range: _monthRange(),
      ),
      onExpenseTap: () => _openTransactionsFiltered(
        type: TransactionType.expense,
        range: _monthRange(),
      ),
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
          title: 'This month'.tr,
          actionLabel: 'Reports'.tr,
          onAction: () => Get.toNamed<void>(AppRoutes.reports),
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(() {
          final PeriodSummary m = controller.month.value;
          final bool positive = m.net >= Decimal.zero;
          // Same privacy rule as the balance card above it.
          final bool hidden = controller.balanceHidden.value;
          String show(String value) => hidden ? '••••' : value;
          return AppCard(
            onTap: () => Get.toNamed<void>(AppRoutes.reports),
            child: IntrinsicHeight(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _Figure(
                      label: 'Income'.tr,
                      value: show(AppFormatters.money(m.income)),
                      color: money.income,
                      onTap: () => _openTransactionsFiltered(
                        type: TransactionType.income,
                        range: _monthRange(),
                      ),
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
                      label: 'Expense'.tr,
                      value: show(AppFormatters.money(m.expense)),
                      color: money.expense,
                      onTap: () => _openTransactionsFiltered(
                        type: TransactionType.expense,
                        range: _monthRange(),
                      ),
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
                      label: 'Net'.tr,
                      value: show(
                        AppFormatters.signedMoney(m.net, positive: positive),
                      ),
                      color: positive ? money.income : money.expense,
                      onTap: () => Get.toNamed<void>(AppRoutes.reports),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Transfers are not counted as income or expense.'.tr,
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
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
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

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: content,
        ),
      ),
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
        Obx(() {
          final bool hasData = controller.monthCategories.isNotEmpty;
          return SectionHeader(
            title: 'Spending overview'.tr,
            actionLabel: hasData ? 'Details'.tr : null,
            onAction: hasData
                ? () => Get.toNamed<void>(AppRoutes.reports)
                : null,
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        Obx(() {
          final List<CategoryTotal> top = controller.monthCategories
              .take(_maxRows)
              .toList();
          if (top.isEmpty) {
            return const _EmptySpendingCard();
          }
          return AppCard(
            onTap: () => Get.toNamed<void>(AppRoutes.reports),
            child: CategoryBreakdown(
              rows: <BreakdownRow>[
                for (int i = 0; i < top.length; i++)
                  BreakdownRow(
                    label:
                        controller.categoryOf(top[i].categoryId)?.name ??
                        'Uncategorised'.tr,
                    icon: CategoryIcons.of(
                      controller.categoryOf(top[i].categoryId)?.icon,
                      TransactionType.expense,
                    ),
                    amount: AppFormatters.money(top[i].amount),
                    share: top[i].share,
                    color: ChartPalette.at(context, i),
                    onTap: () => _openTransactionsFiltered(
                      categoryId: top[i].categoryId,
                      type: TransactionType.expense,
                      range: _monthRange(),
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

/// Rich, engaging empty state shown when no expenses have been recorded yet this month.
class _EmptySpendingCard extends StatelessWidget {
  const _EmptySpendingCard();

  // A getter, so the labels follow a language change.
  static List<({String label, IconData icon})> get _quickCategories => [
    (label: 'Food'.tr, icon: Icons.restaurant_rounded),
    (label: 'Groceries'.tr, icon: Icons.shopping_basket_outlined),
    (label: 'Bills'.tr, icon: Icons.receipt_outlined),
    (label: 'Shopping'.tr, icon: Icons.shopping_bag_outlined),
  ];

  void _openExpenseForm() {
    Get.toNamed<void>(
      AppRoutes.transactionForm,
      arguments: const TransactionFormArgs(type: TransactionType.expense),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? colors.surfaceContainer : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.45),
          width: 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.shadow.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Glowing chart-donut badge
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.07),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.18),
                    width: 2,
                  ),
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      colors.primary.withValues(alpha: 0.22),
                      colors.primary.withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.donut_large_rounded,
                  size: 28,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No expenses recorded this month'.tr,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Keep track of where your money goes. As soon as you log expenses, your category breakdown and visual chart will show here.'
                .tr,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Quick category chips
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final cat in _quickCategories)
                InkWell(
                  onTap: _openExpenseForm,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(cat.icon, size: 14, color: colors.primary),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          cat.label,
                          style: text.labelSmall?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Main action button
          FilledButton.tonalIcon(
            onPressed: _openExpenseForm,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Add your first expense'.tr),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Pro tip banner
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: <Widget>[
                const Text('💡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Tip: Daily tracking uncovers 15–20% in hidden monthly savings!'
                        .tr,
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Entry points to budgets and recurring schedules.
class _PlanSection extends StatelessWidget {
  const _PlanSection();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: 'Plan ahead'.tr),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: _EnhancedPlanTile(
                icon: Icons.savings_outlined,
                iconColor: money.income,
                title: 'Budgets'.tr,
                subtitle: 'Set limits and track spend'.tr,
                onTap: () => Get.toNamed<void>(AppRoutes.budgets),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _EnhancedPlanTile(
                icon: Icons.event_repeat_outlined,
                iconColor: colors.primary,
                title: 'Recurring'.tr,
                subtitle: 'Rent, bills, EMIs on autopilot'.tr,
                onTap: () => Get.toNamed<void>(AppRoutes.recurring),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _EnhancedPlanTile(
                icon: Icons.notifications_active_outlined,
                iconColor: money.payable,
                title: 'Reminders'.tr,
                subtitle: 'Never miss a due date'.tr,
                onTap: () => Get.toNamed<void>(AppRoutes.reminders),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _EnhancedPlanTile(
                icon: Icons.notifications_outlined,
                iconColor: money.receivable,
                title: 'Notifications'.tr,
                subtitle: 'Payment alerts received'.tr,
                onTap: () => Get.toNamed<void>(AppRoutes.notifications),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EnhancedPlanTile extends StatelessWidget {
  const _EnhancedPlanTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(
                icon: icon,
                color: iconColor,
                size: AppSizes.iconBadgeSmall + AppSpacing.xs,
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 11,
                color: colors.outlineVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subtitle,
            style: text.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: 11.5,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
        title: 'Add your first account'.tr,
        message:
            'Create a cash, bank or UPI account with its opening balance. Then you can record income and expenses.'
                .tr,
        actionLabel: 'Add account'.tr,
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
    final FinanceColors money = FinanceColors.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;

    final List<({IconData icon, String label, Color color, VoidCallback onTap})>
    actions = [
      (
        icon: Icons.south_west_rounded,
        label: 'Income'.tr,
        color: money.income,
        onTap: () => _addTransaction(TransactionType.income),
      ),
      (
        icon: Icons.north_east_rounded,
        label: 'Expense'.tr,
        color: money.expense,
        onTap: () => _addTransaction(TransactionType.expense),
      ),
      (
        icon: Icons.add_card_outlined,
        label: 'Credit'.tr,
        color: money.receivable,
        onTap: () => _addEntry(ContactTransactionType.credit),
      ),
      (
        icon: Icons.remove_circle_outline,
        label: 'Debit'.tr,
        color: money.payable,
        onTap: () => _addEntry(ContactTransactionType.debit),
      ),
      (
        icon: Icons.swap_horiz_rounded,
        label: 'Transfer'.tr,
        color: colors.primary,
        onTap: () => Get.toNamed<void>(AppRoutes.transferForm),
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final a in actions)
            Expanded(
              child: Semantics(
                button: true,
                label: a.label,
                excludeSemantics: true,
                child: InkWell(
                  onTap: a.onTap,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconBadge(
                          icon: a.icon,
                          color: a.color,
                          size: AppSizes.quickAction,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // Two lines: 'Udhaar diya' and 'Udhaar liya' would
                        // otherwise both cut to the same 'Udhaar…'.
                        Text(
                          a.label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Today'.tr,
          actionLabel: 'Details'.tr,
          onAction: () => _openTransactionsFiltered(range: _todayRange()),
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(() {
          final bool hidden = controller.balanceHidden.value;
          String show(Object v) => hidden ? '••••' : v.toString();
          return Row(
            children: <Widget>[
              Expanded(
                child: SummaryTile(
                  icon: Icons.south_west_rounded,
                  label: "Today's income".tr,
                  value: show(
                    AppFormatters.money(controller.today.value.income),
                  ),
                  color: money.income,
                  onTap: () => _openTransactionsFiltered(
                    type: TransactionType.income,
                    range: _todayRange(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SummaryTile(
                  icon: Icons.north_east_rounded,
                  label: "Today's expense".tr,
                  value: show(
                    AppFormatters.money(controller.today.value.expense),
                  ),
                  color: money.expense,
                  onTap: () => _openTransactionsFiltered(
                    type: TransactionType.expense,
                    range: _todayRange(),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
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
          title: 'Khata'.tr,
          actionLabel: 'Open'.tr,
          onAction: () => Get.toNamed<void>(AppRoutes.contacts),
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(() {
          if (controller.contactCount.value == 0) {
            return AppCard(
              onTap: () => Get.toNamed<void>(AppRoutes.contactForm),
              padding: EdgeInsets.zero,
              child: AppListTile(
                onTap: () => Get.toNamed<void>(AppRoutes.contactForm),
                leading: const IconBadge(icon: Icons.people_outline),
                title: 'No contacts yet'.tr,
                subtitle:
                    'Track who owes you and who you owe. Add your first contact.'
                        .tr,
                subtitleMaxLines: 3,
                trailing: TextButton(
                  onPressed: () => Get.toNamed<void>(AppRoutes.contactForm),
                  child: Text('Add'.tr),
                ),
              ),
            );
          }
          return Row(
            children: <Widget>[
              Expanded(
                child: SummaryTile(
                  icon: Icons.call_received_rounded,
                  label: 'You will get'.tr,
                  value: AppFormatters.money(controller.khata.value.receivable),
                  color: money.receivable,
                  onTap: () => Get.toNamed<void>(AppRoutes.contacts),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SummaryTile(
                  icon: Icons.call_made_rounded,
                  label: 'You will give'.tr,
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
          title: 'Accounts'.tr,
          actionLabel: 'Manage'.tr,
          onAction: () => Get.toNamed<void>(AppRoutes.accounts),
        ),
        const SizedBox(height: AppSpacing.sm),
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
          title: 'Recent transactions'.tr,
          actionLabel: 'See all'.tr,
          onAction: () => Get.toNamed<void>(AppRoutes.transactions),
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(() {
          if (controller.recent.isEmpty) {
            return AppCard(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions yet'.tr,
                message:
                    'Record your first income or expense to see it here.'.tr,
                actionLabel: 'Add expense'.tr,
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
