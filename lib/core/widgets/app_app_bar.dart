import 'package:flutter/material.dart';

/// Standard app bar; color, elevation and typography come from AppTheme.
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppAppBar({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = true,
    this.showMenu = false,
    this.onProfileTap,
    this.onSettingsTap,
    this.onSignOutTap,
  });

  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final bool showMenu;
  final VoidCallback? onProfileTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onSignOutTap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return AppBar(
      title: Text(
        title,
        style: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: colors.onSurface,
        ),
      ),
      centerTitle: centerTitle,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: colors.surface,
      surfaceTintColor: colors.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: colors.shadow.withValues(alpha: 0.3),
      leadingWidth: 56,
      actions: [
        ...actions,
        if (showMenu)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: colors.onSurfaceVariant,
                size: 26,
              ),
              tooltip: 'More options',
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              color: colors.surface,
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
                _MenuItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  onTap: onProfileTap,
                ),
                _MenuItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: onSettingsTap,
                ),
                _MenuItem(
                  icon: Icons.logout_rounded,
                  label: 'Sign Out',
                  isDestructive: true,
                  onTap: onSignOutTap,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MenuItem extends PopupMenuEntry<String> {
  const _MenuItem({
    required this.icon,
    required this.label,
    this.isDestructive = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback? onTap;

  @override
  double get height => 48;

  @override
  bool represents(String? value) => false;

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
    final Color iconColor = widget.isDestructive
        ? colors.error
        : colors.onSurfaceVariant;

    return InkWell(
      onTap: () {
        widget.onTap?.call();
        Navigator.pop(context);
      },
      onHover: (value) => setState(() => _hovered = value),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _hovered
            ? (widget.isDestructive
                ? colors.errorContainer.withValues(alpha: 0.3)
                : colors.primaryContainer.withValues(alpha: 0.3))
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 22,
              color: iconColor,
            ),
            const SizedBox(width: 14),
            Text(
              widget.label,
              style: textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
