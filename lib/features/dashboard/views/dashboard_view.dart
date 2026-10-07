import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Home tab content. Financial summaries are added in their feature phases.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppContent(
      maxWidth: AppSizes.maxPageWidth,
      child: AppCard(
        child: EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Welcome to ${AppConstants.appName}',
          message: 'Your balances and recent activity will appear here.',
          actionLabel: 'Appearance settings',
          onAction: _openSettings,
        ),
      ),
    );
  }

  static void _openSettings() => Get.toNamed<void>(AppRoutes.settings);
}

/// Explains why a destination is empty until its implementation phase.
class FeaturePlaceholderView extends StatelessWidget {
  const FeaturePlaceholderView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppContent(
      maxWidth: AppSizes.maxPageWidth,
      child: EmptyState(
        icon: icon,
        title: title,
        message: message,
        actionLabel: 'Appearance settings',
        onAction: _openSettings,
      ),
    );
  }

  static void _openSettings() => Get.toNamed<void>(AppRoutes.settings);
}
