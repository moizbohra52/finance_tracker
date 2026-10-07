import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Owns the active [ThemeMode]. The choice lives in memory only; persisting it
/// across restarts belongs to the storage service (Phase 03).
class ThemeController extends GetxController {
  final Rx<ThemeMode> themeMode = ThemeMode.system.obs;

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
  }
}
