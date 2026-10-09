import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_bottom_navigation.dart';
import 'package:finance_tracker/core/widgets/offline_widgets.dart';
import 'package:finance_tracker/features/contacts/views/contact_list_view.dart';
import 'package:finance_tracker/features/dashboard/views/dashboard_view.dart';
import 'package:finance_tracker/features/notifications/widgets/notification_bell.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/profile/views/profile_view.dart';
import 'package:finance_tracker/features/reports/views/reports_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_list_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/features/auth/widgets/confirm_sign_out.dart';
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
  late final NotificationCoordinator _notifications =
      Get.find<NotificationCoordinator>();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // From here a notification tap can open its screen on top of the shell,
    // and one that launched the app is opened now.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _notifications.markShellReady(),
    );
  }

  @override
  void dispose() {
    _notifications.markShellGone();
    super.dispose();
  }

  void _selectDestination(int index) {
    setState(() {
      _visitedDestinations.add(index);
      _selectedIndex = index;
    });
  }

  /// Profile name, else the email's local part, so the title and the avatar
  /// initial always agree.
  static String _displayName(ProfileController profile) {
    final String name = profile.displayName.value.trim();
    if (name.isNotEmpty) return name;
    final String typed = profile.fullNameController.text.trim();
    if (typed.isNotEmpty) return typed;
    final String local = profile.email.split('@').first.trim();
    return local.isNotEmpty ? local : 'User';
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
              final String name = _displayName(profile);
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
            actions: const <Widget>[NotificationBell()],
            showMenu: true,
            profileAvatar: Obx(() {
              final String initial = _displayName(
                profile,
              ).characters.first.toUpperCase();

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
            onSignOutTap: () => confirmAndSignOut(context),
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                const SyncStatusBar(),
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
                                            selectedIcon: Icon(
                                              item.selectedIcon,
                                            ),
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
