import 'package:finance_tracker/theme/app_colors.dart';
import 'package:flutter/material.dart';

ThemeData get appTheme {
  return ThemeData(
    // Use the first color from the logo as the primary color
    primaryColor: AppColors.color1,
    // You can customize the theme further using the other colors
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.color1,
      // secondary: AppColors.color2,
      // surface: AppColors.color3,
      // etc.
    ),
  );
}