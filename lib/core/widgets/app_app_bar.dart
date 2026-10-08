import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _IconColorVariant { primary, secondary, normal }

/// Modern, glassmorphism-inspired App Bar with polished typography,
/// frosted surface, refined back button, profile avatar, and sleek overflow menu.
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions = const <Widget>[],
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = true,
    this.showMenu = false,
    this.profileAvatar,
    this.onProfileTap,
    this.onSettingsTap,
    this.onSignOutTap,
  });

  final String? title;
  final Widget? titleWidget;
  final List<Widget> actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final bool showMenu;
  final Widget? profileAvatar;
  final VoidCallback? onProfileTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onSignOutTap;

  @override
  Size get preferredSize => Size.fromHeight(titleWidget != null ? 62 : 58);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
      title:
          titleWidget ??
          (title != null
              ? Text(
                  title!,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    fontSize: 20,
                    color: colors.onSurface,
                  ),
                )
              : null),
      centerTitle: titleWidget != null ? false : centerTitle,
      leading:
          leading ?? (automaticallyImplyLeading ? const AppBackButton() : null),
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 56,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: isDark ? 0.82 : 0.88),
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(
                    alpha: isDark ? 0.22 : 0.45,
                  ),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (profileAvatar != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: profileAvatar!),
          ),
        ...actions,
        if (showMenu)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: PopupMenuButton<String>(
                tooltip: 'More options',
                elevation: 6,
                shadowColor: Colors.black.withValues(
                  alpha: isDark ? 0.4 : 0.12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colors.outlineVariant.withValues(
                      alpha: isDark ? 0.3 : 0.45,
                    ),
                    width: 1,
                  ),
                ),
                color: isDark ? const Color(0xFF131B2E) : Colors.white,
                offset: const Offset(0, 48),
                onSelected: (String value) {
                  switch (value) {
                    case 'profile':
                      onProfileTap?.call();
                      break;
                    case 'settings':
                      onSettingsTap?.call();
                      break;
                    case 'signout':
                      onSignOutTap?.call();
                      break;
                  }
                },
                itemBuilder: (BuildContext context) => [
                  const _MenuItem(
                    value: 'profile',
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    iconColorVariant: _IconColorVariant.primary,
                  ),
                  const _MenuItem(
                    value: 'settings',
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    iconColorVariant: _IconColorVariant.secondary,
                  ),
                  const _MenuItem(
                    value: 'signout',
                    icon: Icons.logout_rounded,
                    label: 'Sign Out',
                    isDestructive: true,
                  ),
                ],
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: isDark ? 0.35 : 0.55,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(
                        alpha: isDark ? 0.3 : 0.45,
                      ),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.more_vert_rounded,
                    color: colors.onSurface,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.color});

  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bool canPop = ModalRoute.of(context)?.canPop ?? false;
    if (!canPop && onPressed == null) return const SizedBox.shrink();

    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String tooltip = MaterialLocalizations.of(context).backButtonTooltip;

    return Center(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed ?? () => Navigator.maybePop(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(
                  alpha: isDark ? 0.35 : 0.55,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.outlineVariant.withValues(
                    alpha: isDark ? 0.3 : 0.45,
                  ),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 15,
                color: color ?? colors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends PopupMenuEntry<String> {
  const _MenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.iconColorVariant = _IconColorVariant.normal,
    this.isDestructive = false,
  });

  final String value;
  final IconData icon;
  final String label;
  final _IconColorVariant iconColorVariant;
  final bool isDestructive;

  @override
  double get height => 48;

  @override
  bool represents(String? value) => this.value == value;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final Color textColor = widget.isDestructive
        ? colors.error
        : colors.onSurface;

    final Color badgeBg;
    final Color iconColor;
    if (widget.isDestructive) {
      badgeBg = colors.error.withValues(alpha: 0.12);
      iconColor = colors.error;
    } else if (widget.iconColorVariant == _IconColorVariant.primary) {
      badgeBg = colors.primary.withValues(alpha: 0.12);
      iconColor = colors.primary;
    } else if (widget.iconColorVariant == _IconColorVariant.secondary) {
      badgeBg = colors.secondary.withValues(alpha: 0.12);
      iconColor = colors.secondary;
    } else {
      badgeBg = colors.surfaceContainerHighest.withValues(alpha: 0.4);
      iconColor = colors.onSurface;
    }

    return InkWell(
      onTap: () => Navigator.pop(context, widget.value),
      onHover: (value) => setState(() => _hovered = value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _hovered
            ? (widget.isDestructive
                  ? colors.errorContainer.withValues(alpha: 0.25)
                  : colors.primaryContainer.withValues(alpha: 0.25))
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(widget.icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
