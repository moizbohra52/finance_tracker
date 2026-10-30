import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Primary destinations available to signed-in users.
class AppNavigationDestination {
  const AppNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// A getter, so the labels follow a language change.
  static List<AppNavigationDestination> get items => <AppNavigationDestination>[
    AppNavigationDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Home'.tr,
    ),
    AppNavigationDestination(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Transactions'.tr,
    ),
    AppNavigationDestination(
      icon: Icons.people_outline,
      selectedIcon: Icons.people_rounded,
      label: 'Khata'.tr,
    ),
    AppNavigationDestination(
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
      label: 'Reports'.tr,
    ),
    // Profile is not a tab: the avatar in the app bar (and its menu)
    // opens it, so a tab would only duplicate that entry point.
  ];
}

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // A soft, wide shadow lifts the bar off the page in light mode; in dark
    // mode a hairline does the same job.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: isDark
            ? Border(
                top: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.3),
                ),
              )
            : null,
        boxShadow: isDark
            ? null
            : AppShadows.floating(colors.shadow, alpha: 0.1),
      ),
      child: NavigationBarTheme(
        data: Theme.of(context).navigationBarTheme,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: AppNavigationDestination.items
              .map(
                (AppNavigationDestination item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
