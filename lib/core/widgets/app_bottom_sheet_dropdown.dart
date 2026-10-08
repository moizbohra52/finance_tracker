import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// A form field that looks like a dropdown but opens a bottom sheet for
/// selection – consistent with the settings-page picker style.
///
/// [T] is the value type. Every option needs a label via [labelOf]; an optional
/// [detailOf] adds a subtitle line. The field participates in [Form] validation
/// via [validator].
class BottomSheetDropdown<T> extends StatelessWidget {
  const BottomSheetDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.detailOf,
    this.decoration = const InputDecoration(),
    this.validator,
    this.isExpanded = true,
  });

  /// Currently selected value (may be null if nothing is chosen yet).
  final T? value;

  /// All available options.
  final List<T> options;

  /// Converts an option to a user-visible label.
  final String Function(T option) labelOf;

  /// Optional secondary text under each option.
  final String Function(T option)? detailOf;

  /// Called when the user picks an option.
  final ValueChanged<T?> onChanged;

  /// Standard [InputDecoration] – typically just a `labelText`.
  final InputDecoration decoration;

  /// Optional form-level validator.
  final FormFieldValidator<T>? validator;

  /// Whether the field stretches to fill the available width.
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      initialValue: value,
      validator: validator,
      builder: (FormFieldState<T> state) {
        // Resolve the displayed text.
        final String displayText = state.value != null
            ? labelOf(state.value as T)
            : '';

        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () async {
            final T? picked = await _showSheet(context, state.value);
            if (picked != null || options.any((T o) => o == null)) {
              state.didChange(picked);
              onChanged(picked);
            }
          },
          child: InputDecorator(
            decoration: decoration.copyWith(
              errorText: state.hasError ? state.errorText : null,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            isEmpty: displayText.isEmpty,
            child: isExpanded
                ? Text(
                    displayText,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  )
                : Text(
                    displayText,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
          ),
        );
      },
    );
  }

  Future<T?> _showSheet(BuildContext context, T? current) {
    final String title =
        decoration.labelText ?? decoration.hintText ?? 'Choose';
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppSizes.maxContentWidth,
            maxHeight: MediaQuery.sizeOf(sheet).height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Text(
                  title,
                  style: Theme.of(sheet)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final T option in options)
                ListTile(
                  minTileHeight: AppSizes.minTouchTarget,
                  title: Text(labelOf(option)),
                  subtitle:
                      detailOf == null ? null : Text(detailOf!(option)),
                  trailing: option == current
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(sheet).colorScheme.primary,
                        )
                      : null,
                  selected: option == current,
                  onTap: () => Navigator.of(sheet).pop(option),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
