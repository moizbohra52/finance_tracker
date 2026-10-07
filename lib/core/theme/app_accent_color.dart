import 'package:flutter/material.dart';

enum AppAccentColor {
  indigo('indigo', 'Indigo', Color(0xFF4F46E5)),
  violet('violet', 'Violet', Color(0xFF7C3AED)),
  teal('teal', 'Teal', Color(0xFF0F766E)),
  rose('rose', 'Rose', Color(0xFFBE185D));

  const AppAccentColor(this.storageKey, this.label, this.seedColor);

  final String storageKey;
  final String label;
  final Color seedColor;

  static AppAccentColor fromStorageKey(String? key) => values.firstWhere(
    (AppAccentColor accent) => accent.storageKey == key,
    orElse: () => AppAccentColor.indigo,
  );
}
