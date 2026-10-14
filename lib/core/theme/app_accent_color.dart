import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Hand-picked shades of one accent. Generating them from the seed alone
/// darkens bright seeds into muddy colours (yellow turns olive, tan turns
/// khaki) to reach readable contrast, so each accent names its own shades.
///
/// They are deliberately muted (moderate saturation, soft pastels in dark
/// mode) so the app looks calm and professional; the seed's hue is kept.
@immutable
class AccentTones {
  const AccentTones({
    required this.deep,
    required this.light,
    required this.tint,
    required this.ink,
  });

  /// Readable on light surfaces and carries white text: primary in light
  /// mode, filled buttons, and the balance card in both modes.
  final Color deep;

  /// Readable on dark surfaces: primary in dark mode.
  final Color light;

  /// Pale fill for selected chips and containers in light mode.
  final Color tint;

  /// Darkest shade: text on [tint], and on [light] in dark mode.
  final Color ink;
}

/// The accent colours a user can choose. The stored value is [storageKey],
/// so adding an entry never changes what an existing user has saved.
enum AppAccentColor {
  // The four colours of the logo, in the order they appear in it.
  ember(
    'ember',
    'Ember',
    AppColors.logoEmber,
    AccentTones(
      deep: Color(0xFFB5501F),
      light: Color(0xFFF0A27A),
      tint: Color(0xFFFBEBE2),
      ink: Color(0xFF42190A),
    ),
    fromLogo: true,
  ),
  sun(
    'sun',
    'Sun',
    AppColors.logoSun,
    // Antique gold rather than olive: yellow darkened at its own hue looks
    // muddy, and a bright amber looked loud.
    AccentTones(
      deep: Color(0xFF8F6B25),
      light: Color(0xFFE2C27A),
      tint: Color(0xFFF7EFDA),
      ink: Color(0xFF3A2A0A),
    ),
    fromLogo: true,
  ),
  cocoa(
    'cocoa',
    'Cocoa',
    AppColors.logoCocoa,
    AccentTones(
      deep: Color(0xFF7A4A2A),
      light: Color(0xFFD9B293),
      tint: Color(0xFFF3E8DF),
      ink: Color(0xFF2B170A),
    ),
    fromLogo: true,
  ),
  sand(
    'sand',
    'Sand',
    AppColors.logoSand,
    AccentTones(
      deep: Color(0xFF8A6440),
      light: Color(0xFFD8B48A),
      tint: Color(0xFFF5EDE3),
      ink: Color(0xFF33241A),
    ),
    fromLogo: true,
  ),

  indigo(
    'indigo',
    'Indigo',
    AppColors.defaultAccentSeed,
    AccentTones(
      deep: Color(0xFF4B57A8),
      light: Color(0xFFAEB6E6),
      tint: Color(0xFFEAECF8),
      ink: Color(0xFF1E2552),
    ),
  ),
  violet(
    'violet',
    'Violet',
    Color(0xFF7C3AED),
    AccentTones(
      deep: Color(0xFF6A52A3),
      light: Color(0xFFC2B6E6),
      tint: Color(0xFFEFEBF8),
      ink: Color(0xFF2B1F4A),
    ),
  ),
  teal(
    'teal',
    'Teal',
    Color(0xFF0F766E),
    AccentTones(
      deep: Color(0xFF2E6F69),
      light: Color(0xFF8DCBC3),
      tint: Color(0xFFE2F1EF),
      ink: Color(0xFF0F2F2C),
    ),
  ),
  rose(
    'rose',
    'Rose',
    Color(0xFFBE185D),
    AccentTones(
      deep: Color(0xFFA1466A),
      light: Color(0xFFE4AFC2),
      tint: Color(0xFFF8E9EF),
      ink: Color(0xFF3F1628),
    ),
  );

  const AppAccentColor(
    this.storageKey,
    this.label,
    this.seedColor,
    this.tones, {
    this.fromLogo = false,
  });

  final String storageKey;
  final String label;

  /// The colour the accent is named after (the exact logo colour for the
  /// logo accents). Settings shows [AccentTones.deep] on the swatch, the
  /// shade the app actually uses.
  final Color seedColor;

  /// The shades the theme is built from.
  final AccentTones tones;

  /// Whether this is one of the logo's colours.
  final bool fromLogo;

  static List<AppAccentColor> get logoColours =>
      values.where((AppAccentColor a) => a.fromLogo).toList();

  static List<AppAccentColor> get otherColours =>
      values.where((AppAccentColor a) => !a.fromLogo).toList();

  /// Unknown or missing keys fall back to Indigo, the default.
  static AppAccentColor fromStorageKey(String? key) => values.firstWhere(
    (AppAccentColor accent) => accent.storageKey == key,
    orElse: () => AppAccentColor.indigo,
  );
}
