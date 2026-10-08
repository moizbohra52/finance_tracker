import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// The accent colours a user can choose. Each one seeds the whole colour
/// scheme; the stored value is [storageKey], so adding an entry never changes
/// what an existing user has saved.
enum AppAccentColor {
  // The four colours of the logo, in the order they appear in it.
  ember('ember', 'Ember', AppColors.logoEmber, fromLogo: true),
  sun('sun', 'Sun', AppColors.logoSun, fromLogo: true),
  cocoa('cocoa', 'Cocoa', AppColors.logoCocoa, fromLogo: true),
  sand('sand', 'Sand', AppColors.logoSand, fromLogo: true),

  indigo('indigo', 'Indigo', AppColors.defaultAccentSeed),
  violet('violet', 'Violet', Color(0xFF7C3AED)),
  teal('teal', 'Teal', Color(0xFF0F766E)),
  rose('rose', 'Rose', Color(0xFFBE185D));

  const AppAccentColor(
    this.storageKey,
    this.label,
    this.seedColor, {
    this.fromLogo = false,
  });

  final String storageKey;
  final String label;
  final Color seedColor;

  /// Whether this is one of the logo's colours.
  final bool fromLogo;

  /// How the scheme is derived from [seedColor]. The logo colours are vivid,
  /// so they use `fidelity`, which keeps their hue and strength (ember stays
  /// a clear orange-red instead of turning brown); the others keep Material's
  /// default. Both give accessible text colours.
  DynamicSchemeVariant get variant =>
      fromLogo ? DynamicSchemeVariant.fidelity : DynamicSchemeVariant.tonalSpot;

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
