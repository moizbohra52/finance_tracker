import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/charts.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/report_calculator.dart';
import 'package:finance_tracker/features/transactions/controller/calendar_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A month as a calendar: what went out (and whether anything came in) each
/// day, and the transactions of the chosen day.
class CalendarView extends GetView<CalendarController> {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Calendar'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxPageWidth,
          child: Obx(() {
            final String? error = controller.error.value;
            if (error != null) {
              return ErrorState(message: error, onRetry: controller.load);
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              children: <Widget>[
                const _MonthHeader(),
                const SizedBox(height: AppSpacing.sm),
                if (controller.isLoading.value)
                  const LoadingState(message: 'Loading your month')
                else ...<Widget>[
                  const _MonthGrid(),
                  const SizedBox(height: AppSpacing.lg),
                  const _DayList(),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _MonthHeader extends GetView<CalendarController> {
  const _MonthHeader();

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Obx(
      () => Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: controller.previousMonth,
              ),
              Expanded(
                child: Text(
                  AppFormatters.date(controller.month.value, pattern: 'MMMM y'),
                  textAlign: TextAlign.center,
                  style: text.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: controller.nextMonth,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'In ${AppFormatters.money(controller.summary.value.income)}',
                style: text.labelLarge?.copyWith(color: money.income),
              ),
              const SizedBox(width: AppSpacing.lg),
              Text(
                'Out ${AppFormatters.money(controller.summary.value.expense)}',
                style: text.labelLarge?.copyWith(color: money.expense),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends GetView<CalendarController> {
  const _MonthGrid();

  @override
  Widget build(BuildContext context) {
    final int firstWeekday = AppFormatters.preferences.weekStart.weekday;
    return Obx(() {
      final int blanks = CalendarController.leadingBlanks(
        controller.month.value,
        firstWeekday,
      );
      final DateTime selected = controller.selectedDay.value;
      final DateTime today = DateUtils.dateOnly(DateTime.now());
      return GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.8,
        children: <Widget>[
          for (int i = 0; i < 7; i++)
            Center(
              child: Text(
                // 1 Jan 2024 was a Monday, so day N of that week is weekday N.
                AppFormatters.date(
                  DateTime(2024, 1, (firstWeekday - 1 + i) % 7 + 1),
                  pattern: 'E',
                ),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          for (int i = 0; i < blanks; i++) const SizedBox.shrink(),
          for (final TrendPoint day in controller.days)
            _DayCell(
              day: day,
              selected: day.start == selected,
              today: day.start == today,
              onTap: () => controller.selectDay(day.start),
            ),
        ],
      );
    });
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final TrendPoint day;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool spent = day.expense > Decimal.zero;
    final bool received = day.income > Decimal.zero;
    return Semantics(
      button: true,
      selected: selected,
      label: <String>[
        AppFormatters.date(day.start, pattern: 'd MMMM'),
        if (spent) 'spent ${AppFormatters.money(day.expense)}',
        if (received) 'received ${AppFormatters.money(day.income)}',
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: today ? BorderSide(color: colors.primary) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('${day.start.day}', style: text.bodyMedium),
                if (spent)
                  FittedBox(
                    child: Text(
                      compactAmount(day.expense.toDouble()),
                      style: text.labelSmall?.copyWith(color: money.expense),
                    ),
                  ),
                if (received)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: money.income,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayList extends GetView<CalendarController> {
  const _DayList();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final String day = AppFormatters.date(controller.selectedDay.value);
      final List<Transaction> items = controller.dayItems;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(day, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            EmptyState(
              icon: Icons.event_available_outlined,
              title: 'Nothing on this day',
              message: 'No transactions on $day.',
            )
          else
            AppListCard(
              children: <Widget>[
                for (final Transaction t in items)
                  TransactionListItem(
                    padding: AppListTile.flatPadding,
                    transaction: t,
                    title: TransactionListItem.titleFor(
                      t,
                      categoryName: controller.categoryOf(t.categoryId)?.name,
                      nearby: controller.items,
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
            ),
        ],
      );
    });
  }
}
