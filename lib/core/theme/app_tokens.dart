import 'package:flutter/material.dart';

/// Raw colour values. Feature widgets must not reference these directly; read
/// colours through `Theme.of(context).colorScheme` or [FinanceColors] so
/// light/dark variants stay consistent.
abstract final class AppColors {
  /// Placeholder brand seed until final branding is chosen. Kept away from
  /// green/red/blue/amber so it never competes with the money semantics below.
  static const Color brandSeed = Color(0xFF4F46E5);

  // Light variants hold >= 4.5:1 contrast on light surfaces, dark variants
  // on dark surfaces.
  static const Color incomeLight = Color(0xFF15803D);
  static const Color incomeDark = Color(0xFF4ADE80);
  static const Color expenseLight = Color(0xFFB91C1C);
  static const Color expenseDark = Color(0xFFF87171);
  static const Color receivableLight = Color(0xFF0369A1);
  static const Color receivableDark = Color(0xFF38BDF8);
  static const Color payableLight = Color(0xFFB45309);
  static const Color payableDark = Color(0xFFFBBF24);

  /// Money colours used on the gradient balance card, which is always
  /// primary-toned, so they keep contrast in both themes.
  static const Color incomeOnAccent = Color(0xFF4ADE80);
  static const Color expenseOnAccent = Color(0xFFF87171);
}

abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double full = 999;
}

abstract final class AppSizes {
  static const double buttonHeight = 52;

  /// Smallest comfortable touch target (docs/06_UI_UX_GUIDELINES.md).
  static const double minTouchTarget = 48;
  static const double iconLarge = 56;

  /// Keeps status messages readable on tablets instead of stretching edge to
  /// edge.
  static const double maxContentWidth = 420;
  static const double maxPageWidth = 720;
  static const double maxWideContentWidth = 960;
}
