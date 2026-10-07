import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_bottom_navigation.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/features/contacts/views/contact_list_view.dart';
import 'package:finance_tracker/features/dashboard/views/dashboard_view.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
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
    final ProfileController profile = Get.find<ProfileController>();
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    const List<AppNavigationDestination> destinations =
        AppNavigationDestination.items;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool useRail = constraints.maxWidth >= _railBreakpoint;
        return Scaffold(
          appBar: AppAppBar(
            titleWidget: Obx(() {
              final String name = profile.displayName.value.trim().isNotEmpty
                  ? profile.displayName.value.trim()
                  : (profile.fullNameController.text.trim().isNotEmpty
                      ? profile.fullNameController.text.trim()
                      : (profile.email.isNotEmpty
                          ? profile.email.split('@').first
                          : 'User'));
              final String email = profile.email;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      fontSize: 16,
                      color: colors.onSurface,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              );
            }),
            centerTitle: false,
            automaticallyImplyLeading: false,
            showMenu: true,
            profileAvatar: Obx(() {
              final String name = profile.displayName.value.trim().isNotEmpty
                  ? profile.displayName.value.trim()
                  : (profile.fullNameController.text.trim().isNotEmpty
                      ? profile.fullNameController.text.trim()
                      : 'U');
              final String initial =
                  name.isNotEmpty ? name[0].toUpperCase() : 'U';

              return Semantics(
                button: true,
                label: 'Open profile',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Get.toNamed<void>(AppRoutes.profile),
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: colors.primary.withValues(alpha: 0.12),
                      foregroundColor: colors.primary,
                      child: Text(
                        initial,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
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
