import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/domain/entities/saved_login.dart';
import 'package:finance_tracker/features/auth/controllers/account_switch_controller.dart';
import 'package:finance_tracker/features/profile/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shown while the app changes to another signed-in account: the previous
/// account's screens are gone and the next one's home is not built yet.
class SwitchAccountView extends GetView<AccountSwitchController> {
  const SwitchAccountView({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PopScope(
      // Leaving mid-switch would show screens of neither account.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Obx(() {
                final SavedLogin? login = controller.switchingTo.value;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ProfileAvatar(initial: login?.initial ?? ''),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      login == null
                          ? 'Switching account'
                          : 'Switching to ${login.label}',
                      textAlign: TextAlign.center,
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (login != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        login.email,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    const CircularProgressIndicator(),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
