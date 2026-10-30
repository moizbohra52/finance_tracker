import 'dart:async';

import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/features/app_lock/controllers/app_lock_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Covers the whole app while it is locked. Placed above the navigator
/// (GetMaterialApp.builder), so routes, including one a notification tap
/// opened, stay as they are underneath and nothing of them can be seen,
/// focused or read by a screen reader until the user unlocks.
class AppLockGate extends StatelessWidget {
  const AppLockGate({super.key, required this.controller, this.child});

  final AppLockController controller;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final bool locked = controller.locked.value;
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (child != null)
            IgnorePointer(
              ignoring: locked,
              child: FocusScope(canRequestFocus: !locked, child: child!),
            ),
          if (locked) _LockScreen(controller: controller),
        ],
      );
    });
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.controller});

  final AppLockController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.maxContentWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.lock_outline_rounded,
                        size: 56,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '@app is locked'.trParams(<String, String>{
                      'app': AppConstants.appName,
                    }),
                    textAlign: TextAlign.center,
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Unlock with your fingerprint, face or screen lock.'.tr,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Obx(() {
                    final String? message = controller.lockMessage.value;
                    if (message == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: colors.error),
                      ),
                    );
                  }),
                  const SizedBox(height: AppSpacing.xl),
                  Obx(
                    () => AppButton(
                      label: 'Unlock'.tr,
                      icon: Icons.fingerprint_rounded,
                      isLoading: controller.busy.value,
                      onPressed: () => unawaited(controller.unlock()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
