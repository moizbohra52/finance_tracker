import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/views/transaction_filter_sheet.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Opens the income/expense chooser, then the transaction form.
enum _AddChoice { income, expense, transfer }

Future<void> showAddTransactionSheet(BuildContext context) async {
  Widget option(
    BuildContext sheet,
    _AddChoice choice,
    IconData icon,
    String title,
    String subtitle,
  ) => AppListTile(
    leading: IconBadge(icon: icon),
    title: title,
    subtitle: subtitle,
    onTap: () => Navigator.of(sheet).pop(choice),
  );

  final _AddChoice? choice = await showModalBottomSheet<_AddChoice>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          option(
            sheet,
            _AddChoice.income,
            Icons.south_west_rounded,
            'Add income',
            'Money received into an account',
          ),
          option(
            sheet,
            _AddChoice.expense,
            Icons.north_east_rounded,
            'Add expense',
            'Money spent from an account',
          ),
          option(
            sheet,
            _AddChoice.transfer,
            Icons.swap_horiz_rounded,
            'Transfer between accounts',
            'Move money, e.g. from bank to cash',
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
  switch (choice) {
    case null:
      return;
    case _AddChoice.transfer:
      await Get.toNamed<void>(AppRoutes.transferForm);
    case _AddChoice.income || _AddChoice.expense:
      await Get.toNamed<void>(
        AppRoutes.transactionForm,
        arguments: TransactionFormArgs(
          type: choice == _AddChoice.income
              ? TransactionType.income
              : TransactionType.expense,
        ),
      );
  }
}

/// Standalone transaction list route (back-navigable from the dashboard).
class TransactionListView extends StatelessWidget {
  const TransactionListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Transactions'),
      body: const SafeArea(child: TransactionListContent()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddTransactionSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add transaction'),
      ),
    );
  }
}

/// Search, filters and the paged, day-grouped list. Shared by the tab and the
/// standalone route.
class TransactionListContent extends StatefulWidget {
  const TransactionListContent({super.key});

  @override
  State<TransactionListContent> createState() => _TransactionListContentState();
}

class _TransactionListContentState extends State<TransactionListContent> {
  final TransactionController _controller = Get.find<TransactionController>();
  final ScrollController _scroll = ScrollController();
  late final TextEditingController _search = TextEditingController(
    text: _controller.searchText.value,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) _controller.loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppContent(
      child: Column(
        children: <Widget>[
          _SearchBar(searchField: _search),
          const SizedBox(height: AppSpacing.sm),
          const _QuickTypeSelector(),
          const _TransactionSummaryCard(),
          const _ActiveFilters(),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: Obx(() {
              if (_controller.isLoading.value) {
                return const SkeletonList(type: SkeletonType.transaction);
              }
              final String? error = _controller.error.value;
              if (error != null && _controller.items.isEmpty) {
                return ErrorState(message: error, onRetry: _controller.load);
              }
              if (_controller.items.isEmpty) {
                final bool filtered =
                    _controller.hasActiveFilters ||
                    _controller.searchText.value.trim().isNotEmpty;
                return filtered
                    ? EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matching transactions',
                        message: 'Try a different search or clear the filters.',
                        actionLabel: 'Clear filters',
                        onAction: () {
                          _search.clear();
                          _controller.searchText.value = '';
                          _controller.clearFilters();
                        },
                      )
                    : EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No transactions yet',
                        message:
                            'Record your income and expenses to see them here.',
                        actionLabel: 'Add transaction',
                        onAction: () => showAddTransactionSheet(context),
                      );
              }
              return RefreshIndicator(
                onRefresh: _controller.load,
                child: _GroupedList(scroll: _scroll),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends GetView<TransactionController> {
  const _SearchBar({required this.searchField});

  final TextEditingController searchField;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: <Widget>[
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? colors.surfaceContainerLow : colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
                width: 1,
              ),
            ),
            child: TextField(
              controller: searchField,
              textInputAction: TextInputAction.search,
              onChanged: (String v) => controller.searchText.value = v,
              decoration: InputDecoration(
                hintText: 'Search notes, accounts, categories...',
                hintStyle: TextStyle(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: colors.onSurfaceVariant,
                  size: 20,
                ),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: searchField,
                  builder: (BuildContext context, TextEditingValue value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        searchField.clear();
                        controller.searchText.value = '';
                      },
                    );
                  },
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Obx(
          () => Badge(
            isLabelVisible: controller.hasActiveFilters,
            label: Text(
              '${(controller.typeFilter.value != null ? 1 : 0) + (controller.accountFilter.value != null ? 1 : 0) + (controller.categoryFilter.value != null ? 1 : 0) + (controller.rangeFilter.value != null ? 1 : 0)}',
            ),
            child: IconButton.filledTonal(
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                padding: const EdgeInsets.all(12),
              ),
              tooltip: 'Filter transactions',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => showTransactionFilterSheet(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickTypeSelector extends GetView<TransactionController> {
  const _QuickTypeSelector();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Obx(() {
      final TransactionType? current = controller.typeFilter.value;

      Widget pill({
        required String label,
        required bool selected,
        required IconData icon,
        required Color color,
        required VoidCallback onTap,
      }) {
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Material(
            color: selected
                ? (isDark ? colors.primaryContainer : colors.primary)
                : (isDark ? colors.surfaceContainerLow : colors.surface),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
              side: BorderSide(
                color: selected
                    ? Colors.transparent
                    : colors.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
                width: 1,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      icon,
                      size: 14,
                      color: selected
                          ? (isDark ? colors.onPrimaryContainer : colors.onPrimary)
                          : color,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected
                            ? (isDark ? colors.onPrimaryContainer : colors.onPrimary)
                            : colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: <Widget>[
            pill(
              label: 'All',
              selected: current == null,
              icon: Icons.layers_outlined,
              color: colors.onSurfaceVariant,
              onTap: () => controller.applyFilters(
                type: null,
                accountId: controller.accountFilter.value,
                categoryId: controller.categoryFilter.value,
                range: controller.rangeFilter.value,
              ),
            ),
            pill(
              label: 'Expense',
              selected: current == TransactionType.expense,
              icon: Icons.arrow_upward_rounded,
              color: money.expense,
              onTap: () => controller.applyFilters(
                type: current == TransactionType.expense
                    ? null
                    : TransactionType.expense,
                accountId: controller.accountFilter.value,
                categoryId: controller.categoryFilter.value,
                range: controller.rangeFilter.value,
              ),
            ),
            pill(
              label: 'Income',
              selected: current == TransactionType.income,
              icon: Icons.arrow_downward_rounded,
              color: money.income,
              onTap: () => controller.applyFilters(
                type: current == TransactionType.income
                    ? null
                    : TransactionType.income,
                accountId: controller.accountFilter.value,
                categoryId: controller.categoryFilter.value,
                range: controller.rangeFilter.value,
              ),
            ),
            pill(
              label: 'Transfer',
              selected: current == TransactionType.transfer_out,
              icon: Icons.swap_horiz_rounded,
              color: colors.primary,
              onTap: () => controller.applyFilters(
                type: current == TransactionType.transfer_out
                    ? null
                    : TransactionType.transfer_out,
                accountId: controller.accountFilter.value,
                categoryId: controller.categoryFilter.value,
                range: controller.rangeFilter.value,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _TransactionSummaryCard extends GetView<TransactionController> {
  const _TransactionSummaryCard();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final FinanceColors money = FinanceColors.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Obx(() {
      if (controller.items.isEmpty && !controller.isLoading.value) {
        return const SizedBox.shrink();
      }
      final Decimal inflow = controller.totalInflow;
      final Decimal outflow = controller.totalOutflow;
      final Decimal net = controller.netAmount;
      final bool isNetPositive = net >= Decimal.zero;

      return Container(
        margin: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? colors.surfaceContainerLow : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
            width: 1,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            // Inflow
            Expanded(
              child: Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: money.income.withValues(alpha: isDark ? 0.2 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
                      color: money.income,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Income',
                          style: text.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            AppFormatters.money(inflow),
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: money.income,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 28,
              width: 1,
              color: colors.outlineVariant.withValues(alpha: 0.5),
              margin: const EdgeInsets.symmetric(horizontal: 8),
            ),
            // Outflow
            Expanded(
              child: Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: money.expense.withValues(alpha: isDark ? 0.2 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 16,
                      color: money.expense,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Expense',
                          style: text.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            AppFormatters.money(outflow),
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: money.expense,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 28,
              width: 1,
              color: colors.outlineVariant.withValues(alpha: 0.5),
              margin: const EdgeInsets.symmetric(horizontal: 8),
            ),
            // Net
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Net',
                    style: text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${isNetPositive ? '+' : ''}${AppFormatters.money(net)}',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isNetPositive ? money.income : money.expense,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _ActiveFilters extends GetView<TransactionController> {
  const _ActiveFilters();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Widget> chips = <Widget>[
        if (controller.accountFilter.value != null)
          InputChip(
            label: Text(
              controller.accountName(controller.accountFilter.value!),
            ),
            onDeleted: () => controller.applyFilters(
              type: controller.typeFilter.value,
              categoryId: controller.categoryFilter.value,
              range: controller.rangeFilter.value,
            ),
          ),
        if (controller.categoryFilter.value != null)
          InputChip(
            label: Text(
              controller.categoryOf(controller.categoryFilter.value)?.name ??
                  'Category',
            ),
            onDeleted: () => controller.applyFilters(
              type: controller.typeFilter.value,
              accountId: controller.accountFilter.value,
              range: controller.rangeFilter.value,
            ),
          ),
        if (controller.rangeFilter.value != null)
          InputChip(
            label: Text(
              '${AppFormatters.date(controller.rangeFilter.value!.start)} – '
              '${AppFormatters.date(controller.rangeFilter.value!.end)}',
            ),
            onDeleted: () => controller.applyFilters(
              type: controller.typeFilter.value,
              accountId: controller.accountFilter.value,
              categoryId: controller.categoryFilter.value,
            ),
          ),
      ];
      if (chips.isEmpty) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              ...chips,
              ActionChip(
                label: const Text('Clear all'),
                onPressed: controller.clearFilters,
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Rows are either a day header or a transaction.
sealed class _Row {}

class _HeaderRow extends _Row {
  _HeaderRow(this.label, this.count);
  final String label;
  final int count;
}

class _ItemRow extends _Row {
  _ItemRow(this.transaction);
  final Transaction transaction;
}

class _GroupedList extends GetView<TransactionController> {
  const _GroupedList({required this.scroll});

  final ScrollController scroll;

  List<_Row> _rows() {
    final List<_Row> rows = <_Row>[];
    final Map<String, List<Transaction>> grouped = <String, List<Transaction>>{};
    for (final Transaction t in controller.items) {
      final String label = AppFormatters.dayLabel(t.transactionDate);
      grouped.putIfAbsent(label, () => <Transaction>[]).add(t);
    }
    for (final MapEntry<String, List<Transaction>> entry in grouped.entries) {
      rows.add(_HeaderRow(entry.key, entry.value.length));
      for (final Transaction t in entry.value) {
        rows.add(_ItemRow(t));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final List<_Row> rows = _rows();
    final bool loadingMore = controller.isLoadingMore.value;
    return ListView.builder(
      controller: scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: rows.length + (loadingMore ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index >= rows.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return switch (rows[index]) {
          _HeaderRow(:final String label, :final int count) => Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.xs,
              left: 2,
              right: 2,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                          fontSize: 10.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.4),
                    thickness: 1,
                  ),
                ),
              ],
            ),
          ),
          _ItemRow(:final Transaction transaction) => TransactionListItem(
            padding: AppListTile.flatPadding,
            transaction: transaction,
            title: TransactionListItem.titleFor(
              transaction,
              categoryName:
                  controller.categoryOf(transaction.categoryId)?.name,
              nearby: controller.items,
              accountName: controller.accountName,
            ),
            iconKey: controller.categoryOf(transaction.categoryId)?.icon,
            subtitle: controller.accountName(transaction.accountId),
            onTap: () => Get.toNamed<void>(
              AppRoutes.transactionDetail,
              arguments: transaction.id,
            ),
          ),
        };
      },
    );
  });
}
