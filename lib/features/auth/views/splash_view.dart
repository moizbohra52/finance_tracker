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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: AppSizes.iconLarge,
                color: colors.onPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                semanticsLabel: 'Loading',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
