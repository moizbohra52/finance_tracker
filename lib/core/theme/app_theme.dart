import 'package:finance_tracker/core/theme/app_accent_color.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppTheme {
  static ThemeData get light => lightFor(AppAccentColor.indigo);
  static ThemeData get dark => darkFor(AppAccentColor.indigo);

  static ThemeData lightFor(AppAccentColor accent) =>
      _build(Brightness.light, accent.tones);

  static ThemeData darkFor(AppAccentColor accent) =>
      _build(Brightness.dark, accent.tones);

  /// The accent roles come from the accent's hand-picked [AccentTones];
  /// pages, cards, text and lines are neutral greys whatever the accent.
  /// Material derives only the quieter roles (secondary, tertiary, error).
  static ColorScheme _scheme(Brightness brightness, AccentTones tones) {
    final bool isDark = brightness == Brightness.dark;
    final Color primaryContainer = isDark ? tones.deep : tones.tint;
    final Color onPrimaryContainer = isDark ? Colors.white : tones.ink;
    return ColorScheme.fromSeed(
      seedColor: tones.deep,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? tones.light : tones.deep,
      onPrimary: isDark ? tones.ink : Colors.white,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      // Selected chips and segments use the same pair as other selections.
      secondaryContainer: primaryContainer,
      onSecondaryContainer: onPrimaryContainer,
      surfaceTint: Colors.transparent,
      surface: isDark ? AppColors.cardDark : AppColors.cardLight,
      onSurface: isDark ? AppColors.textDark : AppColors.textLight,
      onSurfaceVariant: isDark
          ? AppColors.textMutedDark
          : AppColors.textMutedLight,
      outline: isDark ? AppColors.outlineDark : AppColors.outlineLight,
      outlineVariant: isDark ? AppColors.lineDark : AppColors.lineLight,
      surfaceContainerLowest: isDark ? AppColors.pageDark : AppColors.cardLight,
      surfaceContainerLow: isDark
          ? AppColors.fillLowDark
          : AppColors.fillLowLight,
      surfaceContainer: isDark ? AppColors.fillDark : AppColors.fillLight,
      surfaceContainerHigh: isDark
          ? AppColors.fillHighDark
          : AppColors.fillHighLight,
      surfaceContainerHighest: isDark
          ? AppColors.fillHighestDark
          : AppColors.fillHighestLight,
      inverseSurface: isDark ? AppColors.textDark : AppColors.fillHighestDark,
      onInverseSurface: isDark ? AppColors.fillDark : AppColors.textDark,
    );
  }

  static ThemeData _build(Brightness brightness, AccentTones tones) {
    final bool isDark = brightness == Brightness.dark;
    // White cards on a light grey page, so cards read as separate surfaces
    // without borders.
    final Color scaffoldBg = isDark ? AppColors.pageDark : AppColors.pageLight;
    final ColorScheme colorScheme = _scheme(brightness, tones);
    final Color surfaceColor = colorScheme.surface;

    // Buttons are pills; inputs and cards keep rounded corners.
    const StadiumBorder controlShape = StadiumBorder();
    const Size buttonMinimumSize = Size(64, AppSizes.buttonHeight);

    final TextTheme baseText =
        (isDark
                ? Typography.material2021().white
                : Typography.material2021().black)
            .apply(
              bodyColor: colorScheme.onSurface,
              displayColor: colorScheme.onSurface,
            );

    final TextTheme textTheme = baseText.copyWith(
      displaySmall: baseText.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: baseText.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: baseText.bodyLarge?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      bodySmall: baseText.bodySmall?.copyWith(fontWeight: FontWeight.w400),
      labelLarge: baseText.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      labelMedium: baseText.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: baseText.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[
        if (isDark) FinanceColors.dark else FinanceColors.light,
      ],
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (BuildContext context) =>
            const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
        titleTextStyle: textTheme.titleLarge,
      ),
      // Light: borderless with a soft shadow. Dark: shadows barely show on
      // a dark page, so a faint outline separates the card instead.
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: isDark
              ? BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                )
              : BorderSide.none,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.45 : 0.7,
            ),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: controlShape,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: controlShape,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.45 : 0.7,
            ),
            width: 1.2,
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        // White fields on the grey page, matching the cards.
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.4 : 0.5,
            ),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.4 : 0.5,
            ),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.12),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
              height: 1.2,
            );
          }
          return textTheme.labelSmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
            height: 1.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.primary, size: 24);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant, size: 24);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceColor,
        elevation: 0,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.12),
        indicatorShape: const StadiumBorder(),
        selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.primary,
        ),
        unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurfaceVariant,
        ),
        selectedIconTheme: IconThemeData(color: colorScheme.primary, size: 24),
        unselectedIconTheme: IconThemeData(
          color: colorScheme.onSurfaceVariant,
          size: 24,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        // Material's default is primaryContainer, which is a different
        // colour from the primary that every button uses. With a vivid
        // accent such as Sun the two are far apart (bright yellow against
        // dark gold), so the add button must use the same pair as buttons.
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        // A pill, like every other button.
        shape: const StadiumBorder(),
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
