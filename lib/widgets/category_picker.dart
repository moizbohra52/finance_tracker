import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter/material.dart';

/// Category chips for the income/expense and recurring forms.
///
/// The selected chip has no check mark (the category's own icon stays
/// visible); it is marked by a thicker primary border as well as its fill,
/// so the selection never rests on colour alone. Tapping it again clears it.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.type,
    required this.selectedId,
    required this.onChanged,
    this.onAddNew,
  });

  final List<Category> categories;

  /// Picks the fallback icon for categories without one of their own.
  final TransactionType type;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  /// Shows a "New" chip that creates a category.
  final VoidCallback? onAddNew;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final VoidCallback? onAddNew = this.onAddNew;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final Category c in categories)
          _chip(colors, c, selected: c.id == selectedId),
        if (onAddNew != null)
          ActionChip(
            avatar: Icon(Icons.add_rounded, size: 18, color: colors.primary),
            label: const Text('New'),
            tooltip: 'Create a category',
            onPressed: onAddNew,
          ),
      ],
    );
  }

  Widget _chip(ColorScheme colors, Category c, {required bool selected}) {
    return ChoiceChip(
      showCheckmark: false,
      avatar: Icon(
        CategoryIcons.of(c.icon, type),
        size: 18,
        color: selected ? colors.onPrimaryContainer : colors.onSurfaceVariant,
      ),
      label: Text(c.name),
      selected: selected,
      side: BorderSide(
        color: selected ? colors.primary : colors.outlineVariant,
        width: selected ? 1.5 : 1,
      ),
      onSelected: (bool on) => onChanged(on ? c.id : null),
    );
  }
}
