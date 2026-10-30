import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/features/auth/controllers/splash_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SplashView extends GetView<SplashController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double value, Widget? child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.85 + (0.15 * value),
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadows.floating(colors.primary, alpha: 0.25),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppConstants.appName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Track. Save. Grow.'.tr,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colors.primary,
                  semanticsLabel: 'Loading'.tr,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
