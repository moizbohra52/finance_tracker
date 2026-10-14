import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/features/categories/controller/category_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Creates or edits one of the user's own categories. On save the route
/// returns the category's id, so a form that opened it can select it.
class CategoryFormView extends StatefulWidget {
  const CategoryFormView({super.key});

  @override
  State<CategoryFormView> createState() => _CategoryFormViewState();
}

class _CategoryFormViewState extends State<CategoryFormView> {
  static const int _maxNameLength = 40;

  final CategoryController _controller = Get.find<CategoryController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = CategoryController.newId();
  late final Category? _existing;
  late CategoryType _type;
  late String _icon;

  bool get _isEditing => _existing != null;

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    final CategoryFormArgs formArgs = args is CategoryFormArgs
        ? args
        : const CategoryFormArgs();
    _existing = formArgs.existing;
    _type = _existing?.type ?? formArgs.type;
    _name.text = _existing?.name ?? '';
    _icon = _existing?.icon ?? _defaultIcon(_type);
    _controller.save.error.value = null;
    _controller.deletion.error.value = null;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String _defaultIcon(CategoryType type) =>
      type == CategoryType.income ? 'other_income' : 'other_expense';

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final String? id = await _controller.saveCategory(
      id: _id,
      existing: _existing,
      name: _name.text,
      type: _type,
      icon: _icon,
    );
    if (id == null) return;
    AppSnackbar.show(_isEditing ? 'Category updated' : 'Category added');
    Get.back<dynamic>(result: id);
  }

  Future<void> _delete(Category category) async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete category?',
      message:
          '"${category.name}" will be removed. Transactions, budgets and '
          'schedules that use it keep their amounts.',
    );
    if (!confirmed) return;
    if (await _controller.deleteCategory(category)) {
      AppSnackbar.show('Category deleted');
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Category? existing = _existing;
    return Scaffold(
      appBar: AppAppBar(title: _isEditing ? 'Edit category' : 'New category'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 120,
          child: Form(
            key: _formKey,
            child: ListView(
              children: <Widget>[
                // The kind is fixed once created, so past transactions keep
                // their meaning.
                if (!_isEditing) ...<Widget>[
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
                    onSelectionChanged: (Set<CategoryType> s) => setState(() {
                      // Keep a chosen icon; swap only the kind's default.
                      if (_icon == _defaultIcon(_type)) {
                        _icon = _defaultIcon(s.first);
                      }
                      _type = s.first;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                AppTextField(
                  label: 'Name',
                  controller: _name,
                  autofocus: !_isEditing,
                  helperText: _type == CategoryType.income
                      ? 'An income category'
                      : 'An expense category',
                  textInputAction: TextInputAction.done,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(_maxNameLength),
                  ],
                  validator: (String? v) => _controller.nameError(
                    v ?? '',
                    _type,
                    exceptId: existing?.id,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Icon', style: text.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                _IconChoices(
                  selected: _icon,
                  onChanged: (String key) => setState(() => _icon = key),
                ),
                const SizedBox(height: AppSpacing.lg),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: _isEditing ? 'Save changes' : 'Add category',
                    icon: Icons.check_rounded,
                    isLoading: _controller.save.isBusy.value,
                    onPressed: _submit,
                  ),
                ),
                if (existing != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  SubmitErrorMessage(_controller.deletion),
                  Obx(
                    () => AppButton(
                      label: 'Delete category',
                      icon: Icons.delete_outline,
                      variant: AppButtonVariant.destructive,
                      isLoading: _controller.deletion.isBusy.value,
                      onPressed: () => _delete(existing),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The icons a category can use. The chosen one is ringed in the accent
/// colour as well as tinted, so the choice does not rest on colour alone.
class _IconChoices extends StatelessWidget {
  const _IconChoices({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final String key in CategoryIcons.keys)
          Semantics(
            button: true,
            selected: key == selected,
            label: '${key.replaceAll('_', ' ')} icon',
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onChanged(key),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: key == selected
                        ? colors.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: IconBadge(
                  icon: CategoryIcons.byKey(key),
                  color: key == selected
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
