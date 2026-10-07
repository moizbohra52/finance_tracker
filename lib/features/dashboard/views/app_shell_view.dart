import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_bottom_navigation.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/features/contacts/views/contact_list_view.dart';
import 'package:finance_tracker/features/dashboard/views/dashboard_view.dart';
import 'package:finance_tracker/features/profile/views/profile_view.dart';
import 'package:finance_tracker/features/reports/views/reports_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_list_view.dart';
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

  Future<void> _signOut(BuildContext context) async {
    final AuthRepository auth = Get.find<AuthRepository>();
    await auth.signOut();
    if (context.mounted) {
      // The auth state change will trigger navigation to login via AuthController
    }
  }

  Widget _destination(int index) => switch (index) {
    0 => const DashboardView(),
    1 => const TransactionListContent(),
    2 => const ContactListContent(),
    3 => const ReportsView(),
    4 => const ProfileContent(),
    _ => const SizedBox.shrink(),
  };

  /// The primary action for the current tab, if it has one.
  Widget? _floatingAction(BuildContext context) => switch (_selectedIndex) {
    1 => FloatingActionButton.extended(
      onPressed: () => showAddTransactionSheet(context),
      icon: const Icon(Icons.add),
      label: const Text('Add'),
    ),
    2 => const FloatingActionButton.extended(
      onPressed: openAddContact,
      icon: Icon(Icons.person_add_alt_1_outlined),
      label: Text('Add contact'),
    ),
    _ => null,
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
        final bool isHome = _selectedIndex == 0;
        return Scaffold(
          appBar: AppAppBar(
            title: destinations[_selectedIndex].label,
            centerTitle: true,
            automaticallyImplyLeading: !isHome,
            showMenu: isHome,
            onProfileTap: () => Get.toNamed<void>(AppRoutes.profile),
            onSettingsTap: () => Get.toNamed<void>(AppRoutes.settings),
            onSignOutTap: () => _signOut(context),
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
                            NavigationRailTheme(
                              data: Theme.of(context).navigationRailTheme,
                              child: NavigationRail(
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
          floatingActionButton: _floatingAction(context),
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
