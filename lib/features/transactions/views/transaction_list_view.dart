import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
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
Future<void> showAddTransactionSheet(BuildContext context) async {
  final TransactionType? type = await showModalBottomSheet<TransactionType>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.south_west_rounded),
            title: const Text('Add income'),
            onTap: () => Navigator.of(sheetContext).pop(TransactionType.income),
          ),
          ListTile(
            leading: const Icon(Icons.north_east_rounded),
            title: const Text('Add expense'),
            onTap: () =>
                Navigator.of(sheetContext).pop(TransactionType.expense),
          ),
        ],
      ),
    ),
  );
  if (type == null) return;
  await Get.toNamed<void>(
    AppRoutes.transactionForm,
    arguments: TransactionFormArgs(type: type),
  );
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
        label: const Text('Add'),
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
          const _ActiveFilters(),
          Expanded(
            child: Obx(() {
              if (_controller.isLoading.value) return const SkeletonList();
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
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: searchField,
            textInputAction: TextInputAction.search,
            onChanged: (String v) => controller.searchText.value = v,
            decoration: const InputDecoration(
              hintText: 'Search notes',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Obx(
          () => Badge(
            isLabelVisible: controller.hasActiveFilters,
            child: IconButton.filledTonal(
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
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

class _ActiveFilters extends GetView<TransactionController> {
  const _ActiveFilters();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.hasActiveFilters) return const SizedBox.shrink();
      final List<Widget> chips = <Widget>[
        if (controller.typeFilter.value != null)
          InputChip(
            label: Text(controller.typeFilter.value!.name),
            onDeleted: () => controller.applyFilters(
              accountId: controller.accountFilter.value,
              categoryId: controller.categoryFilter.value,
              range: controller.rangeFilter.value,
            ),
          ),
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
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
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
  _HeaderRow(this.label);
  final String label;
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
    String? lastLabel;
    for (final Transaction t in controller.items) {
      final String label = AppFormatters.dayLabel(t.transactionDate);
      if (label != lastLabel) {
        rows.add(_HeaderRow(label));
        lastLabel = label;
      }
      rows.add(_ItemRow(t));
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
      itemCount: rows.length + (loadingMore ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index >= rows.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return switch (rows[index]) {
          _HeaderRow(:final String label) => Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.lg,
              bottom: AppSpacing.xs,
              left: AppSpacing.xs,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
          ),
          _ItemRow(:final Transaction transaction) => TransactionListItem(
            transaction: transaction,
            title:
                controller.categoryOf(transaction.categoryId)?.name ??
                transaction.type.name,
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
