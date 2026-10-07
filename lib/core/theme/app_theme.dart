import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandSeed,
      brightness: brightness,
    );
    final RoundedRectangleBorder controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
    const Size buttonMinimumSize = Size(64, AppSizes.buttonHeight);

    return ThemeData(
      colorScheme: colorScheme,
      extensions: <ThemeExtension<dynamic>>[
        if (brightness == Brightness.dark)
          FinanceColors.dark
        else
          FinanceColors.light,
      ],
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: controlShape,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
