import 'dart:io';

import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A screen with every kind of text the app draws: plain text, a style made
/// from scratch, the three button kinds (their label replaces the inherited
/// text style instead of merging with it), a field, a chip, the app bar and
/// the navigation bar.
Widget _sampler(ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(
    appBar: AppBar(title: const Text('Title')),
    body: Column(
      children: <Widget>[
        const Text('Body 1,234.50'),
        const Text('From scratch', style: TextStyle(fontSize: 10)),
        FilledButton(onPressed: () {}, child: const Text('Filled')),
        OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
        TextButton(onPressed: () {}, child: const Text('Text button')),
        const TextField(
          decoration: InputDecoration(labelText: 'Label', hintText: 'Hint'),
        ),
        const Chip(label: Text('Chip')),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      destinations: const <Widget>[
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.list), label: 'List'),
      ],
    ),
  ),
);

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'all text uses the bundled font with equal-width digits (${brightness.name})',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _sampler(
            brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
          ),
        );

        final List<TextStyle?> styles = <TextStyle?>[
          for (final RenderParagraph p in tester.renderObjectList(
            find.byType(RichText),
          ))
            // Icons are text in the icon font.
            if (p.text.style?.fontFamily != 'MaterialIcons') p.text.style,
          tester.widget<EditableText>(find.byType(EditableText)).style,
        ];
        // The sampler's ten texts and its field.
        expect(styles.length, greaterThanOrEqualTo(11));
        for (final TextStyle? style in styles) {
          expect(style?.fontFamily, AppTheme.fontFamily, reason: '$style');
          expect(
            style?.fontFeatures,
            contains(const FontFeature.tabularFigures()),
            reason: '$style',
          );
        }
      },
    );
  }

  test('the font named in the theme is the one bundled in pubspec.yaml', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- family: ${AppTheme.fontFamily}\n'));

    final List<String> files = <String>[
      for (final Match m in RegExp(
        r'- asset: (assets/fonts/\S+\.ttf)',
      ).allMatches(pubspec))
        m.group(1)!,
    ];
    // One file per weight the app uses: 400, 500, 600, 700 and 800.
    expect(files, hasLength(5));
    for (final String file in files) {
      expect(File(file).existsSync(), isTrue, reason: file);
    }
  });
}
