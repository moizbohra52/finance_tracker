import 'dart:math' as math;

import 'package:finance_tracker/core/theme/app_accent_color.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG relative luminance and contrast ratio.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

ThemeData _theme(AppAccentColor accent, Brightness brightness) =>
    brightness == Brightness.light
    ? AppTheme.lightFor(accent.seedColor, variant: accent.variant)
    : AppTheme.darkFor(accent.seedColor, variant: accent.variant);

double _hueGap(double a, double b) {
  final double d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

void main() {
  group('the logo colours', () {
    test('are exactly the four colours sampled from the logo', () {
      expect(AppColors.logoEmber, const Color(0xFFE24201));
      expect(AppColors.logoSun, const Color(0xFFF7C401));
      expect(AppColors.logoCocoa, const Color(0xFF7B4013));
      expect(AppColors.logoSand, const Color(0xFFDEAC72));
    });

    test('are offered as accents, seeded with those exact colours', () {
      expect(AppAccentColor.ember.seedColor, AppColors.logoEmber);
      expect(AppAccentColor.sun.seedColor, AppColors.logoSun);
      expect(AppAccentColor.cocoa.seedColor, AppColors.logoCocoa);
      expect(AppAccentColor.sand.seedColor, AppColors.logoSand);
      expect(AppAccentColor.logoColours, <AppAccentColor>[
        AppAccentColor.ember,
        AppAccentColor.sun,
        AppAccentColor.cocoa,
        AppAccentColor.sand,
      ]);
    });

    test('the other accents are untouched and listed separately', () {
      expect(AppAccentColor.otherColours, <AppAccentColor>[
        AppAccentColor.indigo,
        AppAccentColor.violet,
        AppAccentColor.teal,
        AppAccentColor.rose,
      ]);
      expect(AppAccentColor.indigo.seedColor, const Color(0xFF4F46E5));
      expect(AppAccentColor.violet.seedColor, const Color(0xFF7C3AED));
      expect(AppAccentColor.teal.seedColor, const Color(0xFF0F766E));
      expect(AppAccentColor.rose.seedColor, const Color(0xFFBE185D));
    });
  });

  group('saved choices', () {
    test('every accent round-trips through its storage key', () {
      for (final AppAccentColor accent in AppAccentColor.values) {
        expect(AppAccentColor.fromStorageKey(accent.storageKey), accent);
      }
    });

    test('storage keys are unique, so no choice can overwrite another', () {
      final Set<String> keys = AppAccentColor.values
          .map((AppAccentColor a) => a.storageKey)
          .toSet();
      expect(keys.length, AppAccentColor.values.length);
    });

    test('a choice saved before the logo colours existed still loads', () {
      for (final String saved in <String>['indigo', 'violet', 'teal', 'rose']) {
        expect(AppAccentColor.fromStorageKey(saved).storageKey, saved);
      }
    });

    test('nothing saved, or something unknown, falls back to Indigo', () {
      expect(AppAccentColor.fromStorageKey(null), AppAccentColor.indigo);
      expect(AppAccentColor.fromStorageKey('purple'), AppAccentColor.indigo);
    });
  });

  group('readability', () {
    // WCAG AA for normal text. The raw logo colours do not meet it as primary
    // (yellow is 1.6:1 on white), which is why they seed the scheme.
    for (final Brightness brightness in Brightness.values) {
      for (final AppAccentColor accent in AppAccentColor.values) {
        test('${accent.label} in ${brightness.name} mode', () {
          final ColorScheme scheme = _theme(accent, brightness).colorScheme;
          expect(
            _contrast(scheme.primary, scheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: 'primary text on the surface',
          );
          expect(
            _contrast(scheme.onPrimary, scheme.primary),
            greaterThanOrEqualTo(4.5),
            reason: 'label on a primary button',
          );
          expect(
            _contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
            greaterThanOrEqualTo(4.5),
            reason: 'text on a selected chip or pill',
          );
        });
      }
    }

    test('the raw logo colours alone would not have been readable', () {
      // Documents why they are seeds and not the primary colour.
      const Color white = Colors.white;
      expect(_contrast(AppColors.logoSun, white), lessThan(3));
      expect(_contrast(AppColors.logoSand, white), lessThan(3));
    });
  });

  group('the logo still shows in the theme', () {
    test('each logo accent keeps the logo colour\'s hue', () {
      for (final AppAccentColor accent in AppAccentColor.logoColours) {
        final double logoHue = HSLColor.fromColor(accent.seedColor).hue;
        for (final Brightness brightness in Brightness.values) {
          final double hue = HSLColor.fromColor(
            _theme(accent, brightness).colorScheme.primary,
          ).hue;
          expect(
            _hueGap(hue, logoHue),
            lessThan(15),
            reason: '${accent.label} ${brightness.name}: hue $hue vs $logoHue',
          );
        }
      }
    });

    test('ember stays a vivid orange-red rather than turning brown', () {
      final Color primary = _theme(
        AppAccentColor.ember,
        Brightness.light,
      ).colorScheme.primary;
      // Strong colour: saturation well above a muddy brown's.
      expect(HSLColor.fromColor(primary).saturation, greaterThan(0.9));
    });
  });
}
