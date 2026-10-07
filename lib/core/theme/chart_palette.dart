import 'package:flutter/material.dart';

/// Series colours for category charts, derived from the active theme so they
/// follow light/dark mode and the chosen accent. Colour is never the only
/// signal: charts are always paired with a labelled legend.
abstract final class ChartPalette {
  static List<Color> of(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return <Color>[
      c.primary,
      c.tertiary,
      c.secondary,
      c.error,
      c.primaryContainer,
      c.tertiaryContainer,
      c.outline,
    ];
  }

  /// Colour for the [index]th series; wraps around.
  static Color at(BuildContext context, int index) {
    final List<Color> colors = of(context);
    return colors[index % colors.length];
  }
}
