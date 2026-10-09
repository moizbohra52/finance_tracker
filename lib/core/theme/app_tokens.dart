import 'package:flutter/material.dart';

/// Raw colour values. Feature widgets must not reference these directly; read
/// colours through `Theme.of(context).colorScheme` or [FinanceColors] so
/// light/dark variants stay consistent.
abstract final class AppColors {
  /// The four colours of the app logo (assets/logo.png), sampled from its
  /// flat areas. They seed the logo accents in AppAccentColor, which Material
  /// turns into accessible roles. They are not used as `primary` directly:
  /// on white, yellow is 1.6:1 and sand 2.0:1, far below the 4.5:1 text needs
  /// (see docs/06_UI_UX_GUIDELINES.md). Use them for swatches and branding,
  /// not for text.
  static const Color logoEmber = Color(0xFFE24201);
  static const Color logoSun = Color(0xFFF7C401);
  static const Color logoCocoa = Color(0xFF7B4013);
  static const Color logoSand = Color(0xFFDEAC72);

  /// Seed of the default accent (Indigo). The logo colours are offered as
  /// accents rather than made the default because ember and sun sit close to
  /// the expense (red) and payable (amber) colours below.
  static const Color defaultAccentSeed = Color(0xFF4F46E5);

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

  /// Bottom padding for a scrolling list under an extended FAB, so the last
  /// row (and its amount) is never hidden behind the button.
  static const double fabClearance = 88;
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

  /// Tinted icon badge in list rows and cards.
  static const double iconBadge = 40;

  /// Keeps status messages readable on tablets instead of stretching edge to
  /// edge.
  static const double maxContentWidth = 420;
  static const double maxPageWidth = 720;
  static const double maxWideContentWidth = 960;

  static const double chartHeightSmall = 160;
  static const double chartHeight = 200;

  /// Progress bars and other value changes that should read as motion.
  static const Duration slowAnimation = Duration(milliseconds: 350);
}
