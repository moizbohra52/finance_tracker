import 'package:finance_tracker/core/theme/app_accent_color.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _theme(AppAccentColor accent, Brightness brightness) =>
    brightness == Brightness.light
    ? AppTheme.lightFor(accent.seedColor, variant: accent.variant)
    : AppTheme.darkFor(accent.seedColor, variant: accent.variant);

/// The fill colour of the button's Material.
Color _fill(WidgetTester tester, Finder button) => tester
    .widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)).first,
    )
    .color!;

void main() {
  group('the add (floating) button matches the other buttons', () {
    for (final Brightness brightness in Brightness.values) {
      for (final AppAccentColor accent in AppAccentColor.values) {
        testWidgets('${accent.label} in ${brightness.name} mode', (
          WidgetTester tester,
        ) async {
          final ThemeData theme = _theme(accent, brightness);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Go'),
                  ),
                ),
                floatingActionButton: FloatingActionButton.extended(
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ),
            ),
          );

          final Color button = _fill(tester, find.byType(FilledButton));
          final Color fab = _fill(tester, find.byType(FloatingActionButton));

          expect(button, theme.colorScheme.primary);
          expect(
            fab,
            button,
            reason: 'the add button must be the same colour as a filled button',
          );
        });
      }
    }

    testWidgets('and its icon and label use the same on-colour as buttons', (
      WidgetTester tester,
    ) async {
      final ThemeData theme = _theme(AppAccentColor.sun, Brightness.light);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
        ),
      );

      final Icon icon = tester.widget<Icon>(find.byIcon(Icons.add));
      final IconTheme iconTheme = tester.widget<IconTheme>(
        find
            .descendant(
              of: find.byType(FloatingActionButton),
              matching: find.byType(IconTheme),
            )
            .first,
      );
      expect(icon.color ?? iconTheme.data.color, theme.colorScheme.onPrimary);
    });
  });
}
