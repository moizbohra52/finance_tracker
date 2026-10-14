import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/categories/controller/category_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The categories of one kind (expense or income): the user's own, which
/// can be added, edited and deleted, then the built-in ones, which are
/// read-only.
class CategoryListView extends StatefulWidget {
  const CategoryListView({super.key});

  @override
  State<CategoryListView> createState() => _CategoryListViewState();
}

class _CategoryListViewState extends State<CategoryListView> {
  final CategoryController _controller = Get.find<CategoryController>();
  CategoryType _type = CategoryType.expense;

  TransactionType get _iconType => _type == CategoryType.income
      ? TransactionType.income
      : TransactionType.expense;

  void _open(Category? existing) => Get.toNamed<dynamic>(
    AppRoutes.categoryForm,
    arguments: CategoryFormArgs(type: _type, existing: existing),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Categories'),
      body: SafeArea(
        child: Obx(() {
          if (_controller.isLoading.value) {
            return const AppContent(
              child: SkeletonList(count: 6, type: SkeletonType.account),
            );
          }
          final String? error = _controller.error.value;
          if (error != null && _controller.categories.isEmpty) {
            return ErrorState(message: error, onRetry: _controller.load);
          }
          final List<Category> rows = _controller.ofType(_type);
          final List<Category> own = rows
              .where((Category c) => !c.isSystem)
              .toList();
          final List<Category> builtIn = rows
              .where((Category c) => c.isSystem)
              .toList();
          return AppContent(
            child: RefreshIndicator(
              onRefresh: _controller.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: AppSpacing.fabClearance),
                children: <Widget>[
                  SegmentedButton<CategoryType>(
                    segments: const <ButtonSegment<CategoryType>>[
                      ButtonSegment<CategoryType>(
                        value: CategoryType.expense,
                        icon: Icon(Icons.north_east_rounded),
                        label: Text('Expense'),
                      ),
                      ButtonSegment<CategoryType>(
                        value: CategoryType.income,
                        icon: Icon(Icons.south_west_rounded),
                        label: Text('Income'),
                      ),
                    ],
                    selected: <CategoryType>{_type},
                    onSelectionChanged: (Set<CategoryType> s) =>
                        setState(() => _type = s.first),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Your categories'),
                  const SizedBox(height: AppSpacing.sm),
                  if (own.isEmpty)
                    InlineMessage(
                      tone: InlineMessageTone.info,
                      icon: Icons.category_outlined,
                      announce: false,
                      message: _type == CategoryType.income
                          ? 'Add your own, such as "Side income" or "Rent '
                                'received". They appear when you add income.'
                          : 'Add your own, such as "Pet care" or "Gym". They '
                                'appear when you add an expense.',
                    )
                  else
                    AppListCard(
                      children: <Widget>[
                        for (final Category c in own)
                          AppListTile(
                            leading: IconBadge(
                              icon: CategoryIcons.of(c.icon, _iconType),
                            ),
                            title: c.name,
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _open(c),
                          ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Built-in'),
                  const SizedBox(height: AppSpacing.sm),
                  AppListCard(
                    children: <Widget>[
                      for (final Category c in builtIn)
                        AppListTile(
                          leading: IconBadge(
                            icon: CategoryIcons.of(c.icon, _iconType),
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          title: c.name,
                          trailing: Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                            semanticLabel: 'Built-in, cannot be changed',
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(null),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
    );
  }
}
