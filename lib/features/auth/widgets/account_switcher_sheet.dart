import 'dart:async';

import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/domain/entities/saved_login.dart';
import 'package:finance_tracker/features/auth/controllers/account_switch_controller.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/profile/widgets/profile_avatar.dart';
import 'package:finance_tracker/features/settings/widgets/settings_widgets.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Lists the accounts signed in on this device; tapping one switches to it.
Future<void> showAccountSwitcher(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheet) => const AccountSwitcherSheet(),
    );

/// Settings row that opens the account switcher.
class SwitchAccountTile extends GetView<AccountSwitchController> {
  const SwitchAccountTile({super.key});

  @override
  Widget build(BuildContext context) => Obx(() {
    final int count = controller.logins.length;
    return SettingsTile(
      icon: Icons.switch_account_outlined,
      title: 'Switch account',
      subtitle: count > 1
          ? '$count accounts on this device'
          : 'Sign in to another account',
      onTap: () => showAccountSwitcher(context),
    );
  });
}

class AccountSwitcherSheet extends GetView<AccountSwitchController> {
  const AccountSwitcherSheet({super.key});

  void _switch(BuildContext context, SavedLogin login) {
    Navigator.of(context).pop();
    unawaited(controller.switchTo(login.userId));
  }

  void _add(BuildContext context) {
    Navigator.of(context).pop();
    if (!controller.canAddAccount) {
      AppSnackbar.show(AccountSwitchController.limitMessage);
      return;
    }
    unawaited(Get.toNamed<void>(AppRoutes.addAccount));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: AppSizes.maxContentWidth,
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Obx(() {
        final List<SavedLogin> logins = controller.logins.toList();
        final String? activeId = controller.activeUserId;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                'Switch account',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final SavedLogin login in logins)
              _AccountRow(
                login: login,
                active: login.userId == activeId,
                onTap: login.userId == activeId
                    ? () => Navigator.of(context).pop()
                    : () => _switch(context, login),
              ),
            const Divider(height: AppSpacing.md),
            ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: colors.primary.withValues(alpha: 0.12),
                child: Icon(
                  Icons.person_add_alt_1_outlined,
                  color: colors.primary,
                ),
              ),
              title: const Text('Sign in to another account'),
              subtitle: controller.canAddAccount
                  ? null
                  : const Text(AccountSwitchController.limitMessage),
              onTap: () => _add(context),
            ),
          ],
        );
      }),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.login,
    required this.active,
    required this.onTap,
  });

  final SavedLogin login;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    // Only the active account's photo can be shown: a photo link is signed
    // with that account's session and expires within the hour.
    final ProfileController? profile =
        active && Get.isRegistered<ProfileController>()
        ? Get.find<ProfileController>()
        : null;

    return Semantics(
      selected: active,
      child: ListTile(
        leading: profile == null
            ? ProfileAvatar(initial: login.initial, radius: 20)
            : Obx(
                () => ProfileAvatar(
                  initial: login.initial,
                  link: profile.avatarLink.value,
                  radius: 20,
                ),
              ),
        title: Text(login.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          login.email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: active
            ? Icon(Icons.check_circle_rounded, color: colors.primary)
            : null,
        onTap: onTap,
      ),
    );
  }
}
