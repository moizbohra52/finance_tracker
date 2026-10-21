import 'dart:async';

import 'package:finance_tracker/core/services/avatar_cache.dart';
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
      title: 'Switch account'.tr,
      subtitle: count > 1
          ? '@count accounts on this device'.trParams(<String, String>{
              'count': '$count',
            })
          : 'Sign in to another account'.tr,
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

  void _confirmRemove(BuildContext context, SavedLogin login) {
    showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Remove account?'.tr),
        content: Text(
          'Remove @name (@email) from this device? You can sign in to it again later.'
              .trParams(<String, String>{
                'name': login.label,
                'email': login.email,
              }),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Remove'.tr),
          ),
        ],
      ),
    ).then((bool? confirmed) {
      if (confirmed == true) {
        controller.removeSavedAccount(login.userId);
      }
    });
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
                'Switch account'.tr,
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
                onRemove: login.userId == activeId
                    ? null
                    : () => _confirmRemove(context, login),
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
              title: Text('Sign in to another account'.tr),
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

class _AccountRow extends StatefulWidget {
  const _AccountRow({
    required this.login,
    required this.active,
    required this.onTap,
    this.onRemove,
  });

  final SavedLogin login;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  String? _localAvatar;

  @override
  void initState() {
    super.initState();
    _checkAvatar();
  }

  @override
  void didUpdateWidget(_AccountRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.login.userId != oldWidget.login.userId ||
        widget.login.avatarUrl != oldWidget.login.avatarUrl) {
      _checkAvatar();
    }
  }

  Future<void> _checkAvatar() async {
    final String? url = widget.login.avatarUrl;
    if (url != null && url.isNotEmpty) {
      if (mounted) setState(() => _localAvatar = url);
      return;
    }
    final String? cached = await AvatarCache.getCachedPath(widget.login.userId);
    if (cached != null && mounted) {
      setState(() => _localAvatar = cached);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ProfileController? profile =
        widget.active && Get.isRegistered<ProfileController>()
        ? Get.find<ProfileController>()
        : null;

    final String? fallbackAvatar = _localAvatar ?? widget.login.avatarUrl;

    return Semantics(
      selected: widget.active,
      child: ListTile(
        leading: widget.active && profile != null
            ? Obx(
                () => ProfileAvatar(
                  initial: widget.login.initial,
                  link: profile.avatarLink.value ?? fallbackAvatar,
                  radius: 20,
                ),
              )
            : ProfileAvatar(
                initial: widget.login.initial,
                link: fallbackAvatar,
                radius: 20,
              ),
        title: Text(
          widget.login.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          widget.login.email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: widget.active
            ? Icon(Icons.check_circle_rounded, color: colors.primary)
            : widget.onRemove != null
            ? IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                tooltip: 'Remove account'.tr,
                onPressed: widget.onRemove,
              )
            : null,
        onTap: widget.onTap,
      ),
    );
  }
}
