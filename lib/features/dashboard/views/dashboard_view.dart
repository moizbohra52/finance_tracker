import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Signed-in entry screen placeholder. Replaced by the app shell with bottom
/// navigation in Phase 03.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: const <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          IconButton(
            tooltip: 'Profile',
            icon: Icon(Icons.person_outline),
            onPressed: _openProfile,
          ),
        ],
      ),
      body: const SafeArea(
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

  static void _openProfile() => Get.toNamed<void>(AppRoutes.profile);
}
