import 'package:flutter/material.dart';

/// Raw colour values. Feature widgets must not reference these directly; read
/// colours through `Theme.of(context).colorScheme` or [FinanceColors] so
/// light/dark variants stay consistent.
abstract final class AppColors {
  /// The four colours of the app logo (assets/logo.png), sampled from its
  /// flat areas. They are the swatches of the logo accents in AppAccentColor,
  /// whose hand-picked shades (AccentTones) the theme uses. They are not used
  /// as `primary` directly: on white, yellow is 1.6:1 and sand 2.0:1, far
  /// below the 4.5:1 text needs (see docs/06_UI_UX_GUIDELINES.md). Use them
  /// for swatches and branding, not for text.
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

  // Neutral greys for pages, cards, text and lines. They carry no tint of
  // the accent, so every accent sits on the same clean background (a navy or
  // accent-tinted grey clashed with warm accents such as Sun).
  static const Color pageLight = Color(0xFFF4F5F7);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF111418);
  static const Color textMutedLight = Color(0xFF4D5560);
  static const Color outlineLight = Color(0xFF8A919C);
  static const Color lineLight = Color(0xFFDDE0E5);
  static const Color fillLowLight = Color(0xFFF8F9FA);
  static const Color fillLight = Color(0xFFF2F3F5);
  static const Color fillHighLight = Color(0xFFECEEF1);
  static const Color fillHighestLight = Color(0xFFE4E6EA);

  static const Color pageDark = Color(0xFF0E1014);
  static const Color cardDark = Color(0xFF181B21);
  static const Color textDark = Color(0xFFECEEF1);
  static const Color textMutedDark = Color(0xFFA3AAB5);
  static const Color outlineDark = Color(0xFF6E7682);
  static const Color lineDark = Color(0xFF2E333C);
  static const Color fillLowDark = Color(0xFF14171C);
  static const Color fillDark = Color(0xFF1C2027);
  static const Color fillHighDark = Color(0xFF23272F);
  static const Color fillHighestDark = Color(0xFF2B3039);
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

  /// Tinted icon badge (IconBadge) leading list rows and cards.
  static const double iconBadge = 44;

  /// Smaller badge inside compact tiles such as SummaryTile.
  static const double iconBadgeSmall = 32;

  /// Quick action circles on the home screen.
  static const double quickAction = 48;

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
