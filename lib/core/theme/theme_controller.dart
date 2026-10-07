import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/theme/app_accent_color.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Owns and persists the appearance settings used by the app shell.
class ThemeController extends GetxController {
  ThemeController(this._storage)
    : themeMode = _restoreThemeMode(_storage.readThemeMode()).obs,
      accentColor = AppAccentColor.fromStorageKey(
        _storage.readAccentColor(),
      ).obs;

  final StorageService _storage;
  final Rx<ThemeMode> themeMode;
  final Rx<AppAccentColor> accentColor;

  Future<void> setThemeMode(ThemeMode mode) async {
    final ThemeMode previous = themeMode.value;
    if (mode == previous) return;
    themeMode.value = mode;
    try {
      await _storage.saveThemeMode(mode.name);
    } on AppException catch (error) {
      themeMode.value = previous;
      AppSnackbar.show(error.message);
    }
  }

  Future<void> setAccentColor(AppAccentColor color) async {
    final AppAccentColor previous = accentColor.value;
    if (color == previous) return;
    accentColor.value = color;
    try {
      await _storage.saveAccentColor(color.storageKey);
    } on AppException catch (error) {
      accentColor.value = previous;
      AppSnackbar.show(error.message);
    }
  }

  static ThemeMode _restoreThemeMode(String? value) {
    for (final ThemeMode mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return ThemeMode.system;
  }
}
