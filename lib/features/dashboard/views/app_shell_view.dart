import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_bottom_navigation.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/features/dashboard/views/dashboard_view.dart';
import 'package:finance_tracker/features/profile/views/profile_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Responsive signed-in shell for the app's primary destinations.
class AppShellView extends StatefulWidget {
  const AppShellView({super.key});

  @override
  State<AppShellView> createState() => _AppShellViewState();
}

class _AppShellViewState extends State<AppShellView> {
  static const double _railBreakpoint = 840;

  final Set<int> _visitedDestinations = <int>{0};
  int _selectedIndex = 0;

  void _selectDestination(int index) {
    setState(() {
      _visitedDestinations.add(index);
      _selectedIndex = index;
    });
  }

  void _openSettings() => Get.toNamed<void>(AppRoutes.settings);

  Widget _destination(int index) => switch (index) {
    0 => const DashboardView(),
    1 => const FeaturePlaceholderView(
      icon: Icons.receipt_long_outlined,
      title: 'Transactions',
      message: 'Your income and expenses will appear here.',
    ),
    2 => const FeaturePlaceholderView(
      icon: Icons.people_outline,
      title: 'Khata',
      message: 'Your credit and debit ledger will appear here.',
    ),
    3 => const FeaturePlaceholderView(
      icon: Icons.insights_outlined,
      title: 'Reports',
      message: 'Your financial reports will appear here.',
    ),
    4 => const ProfileContent(),
    _ => const SizedBox.shrink(),
  };

  Widget _pageStack() => IndexedStack(
    index: _selectedIndex,
    children: List<Widget>.generate(
      AppNavigationDestination.items.length,
      (int index) => _visitedDestinations.contains(index)
          ? _destination(index)
          : const SizedBox.shrink(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ConnectivityService connectivity = Get.find<ConnectivityService>();
    const List<AppNavigationDestination> destinations =
        AppNavigationDestination.items;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool useRail = constraints.maxWidth >= _railBreakpoint;
        return Scaffold(
          appBar: AppAppBar(
            title: destinations[_selectedIndex].label,
            automaticallyImplyLeading: false,
            actions: <Widget>[
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Obx(
                  () => connectivity.isOffline
                      ? const OfflineBanner()
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: useRail
                      ? Row(
                          children: <Widget>[
                            NavigationRail(
                              selectedIndex: _selectedIndex,
                              labelType: NavigationRailLabelType.all,
                              onDestinationSelected: _selectDestination,
                              destinations: destinations
                                  .map(
                                    (AppNavigationDestination item) =>
                                        NavigationRailDestination(
                                          icon: Icon(item.icon),
                                          selectedIcon: Icon(item.selectedIcon),
                                          label: Text(item.label),
                                        ),
                                  )
                                  .toList(),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: _pageStack()),
                          ],
                        )
                      : _pageStack(),
                ),
              ],
            ),
          ),
          bottomNavigationBar: useRail
              ? null
              : AppBottomNavigation(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectDestination,
                ),
        );
      },
    );
  }
}
