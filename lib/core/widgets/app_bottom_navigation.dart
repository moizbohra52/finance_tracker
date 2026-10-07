import 'package:flutter/material.dart';

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

  static const List<AppNavigationDestination> items =
      <AppNavigationDestination>[
        AppNavigationDestination(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
          label: 'Home',
        ),
        AppNavigationDestination(
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          label: 'Transactions',
        ),
        AppNavigationDestination(
          icon: Icons.people_outline,
          selectedIcon: Icons.people_rounded,
          label: 'Khata',
        ),
        AppNavigationDestination(
          icon: Icons.insights_outlined,
          selectedIcon: Icons.insights_rounded,
          label: 'Reports',
        ),
        AppNavigationDestination(
          icon: Icons.person_outline,
          selectedIcon: Icons.person_rounded,
          label: 'Profile',
        ),
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
    return NavigationBarTheme(
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
    );
  }
}
