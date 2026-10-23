import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:finance_tracker/features/contacts/services/device_contacts_service.dart';
import 'package:finance_tracker/features/contacts/views/device_contact_picker_sheet.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/contact_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void openAddContact() => Get.toNamed<void>(AppRoutes.contactForm);

Future<void> openImportDeviceContact(BuildContext context) async {
  final DeviceContactData? picked = await showDeviceContactPicker(context);
  if (picked != null) {
    await Get.toNamed<void>(
      AppRoutes.contactForm,
      arguments: <String, dynamic>{'initialDeviceContact': picked},
    );
  }
}

/// Standalone khata route (back-navigable from the dashboard).
class ContactListView extends StatelessWidget {
  const ContactListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: 'Khata'.tr,
        actions: <Widget>[
          IconButton(
            tooltip: 'Import from phone contacts'.tr,
            icon: const Icon(Icons.contacts_outlined),
            onPressed: () => openImportDeviceContact(context),
          ),
        ],
      ),
      body: const SafeArea(child: ContactListContent()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openAddContact,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text('Add contact'.tr),
      ),
    );
  }
}

/// Summary, search, filter and contact list. Shared by the tab and the route.
class ContactListContent extends GetView<ContactController> {
  const ContactListContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const AppContent(child: SkeletonList(type: SkeletonType.khata));
      }
      final String? error = controller.error.value;
      if (error != null && !controller.hasContacts) {
        return ErrorState(message: error, onRetry: controller.load);
      }
      if (!controller.hasContacts) {
        return EmptyState(
          icon: Icons.people_outline,
          title: 'No contacts yet'.tr,
          message:
              'Add the people you lend to or borrow from, then record credit and debit entries against them.'.tr,
          actionLabel: 'Add contact'.tr,
          onAction: openAddContact,
        );
      }
      final List<ContactBalance> rows = controller.visible;
      return AppContent(
        child: RefreshIndicator(
          onRefresh: controller.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              const SliverToBoxAdapter(child: _Summary()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              const SliverToBoxAdapter(child: _SearchAndFilter()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              if (rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matching contacts'.tr,
                    message: 'Try a different name or filter.'.tr,
                  ),
                )
              else
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (BuildContext context, int index) =>
                      ContactBalanceTile(
                        padding: AppListTile.flatPadding,
                        row: rows[index],
                        onTap: () => Get.toNamed<void>(
                          AppRoutes.contactDetail,
                          arguments: rows[index].contact.id,
                        ),
                      ),
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 120),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _Summary extends GetView<ContactController> {
  const _Summary();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Obx(() {
      final Decimal receivable = controller.summary.value.receivable;
      final Decimal payable = controller.summary.value.payable;
      final Decimal net = receivable - payable;
      final bool isNetPositive = net >= Decimal.zero;

      Widget heroCard({
        required String label,
        required String amount,
        required String subtitle,
        required IconData icon,
        required Color color,
        required bool isSelected,
        required VoidCallback onTap,
      }) {
        return Material(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.25 : 0.15)
              : (isDark ? colors.surfaceContainerLow : colors.surface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(
              color: isSelected
                  ? color
                  : colors.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          elevation: isDark ? 0 : 0.5,
          shadowColor: Colors.black.withValues(alpha: 0.05),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: isDark ? 0.25 : 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 18, color: color),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Active'.tr,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    style: text.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      amount,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: -0.3,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: heroCard(
                  label: 'You will get'.tr,
                  amount: AppFormatters.money(receivable),
                  subtitle:
                      controller.receivableCount == 1
                      ? '1 contact'.tr
                      : '@count contacts'.trParams(<String, String>{
                          'count': '${controller.receivableCount}',
                        }),
                  icon: Icons.arrow_downward_rounded,
                  color: money.receivable,
                  isSelected:
                      controller.filter.value == KhataFilter.receivable,
                  onTap: () {
                    controller.filter.value =
                        controller.filter.value == KhataFilter.receivable
                            ? KhataFilter.all
                            : KhataFilter.receivable;
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: heroCard(
                  label: 'You will give'.tr,
                  amount: AppFormatters.money(payable),
                  subtitle:
                      controller.payableCount == 1
                      ? '1 contact'.tr
                      : '@count contacts'.trParams(<String, String>{
                          'count': '${controller.payableCount}',
                        }),
                  icon: Icons.arrow_upward_rounded,
                  color: money.payable,
                  isSelected: controller.filter.value == KhataFilter.payable,
                  onTap: () {
                    controller.filter.value =
                        controller.filter.value == KhataFilter.payable
                            ? KhataFilter.all
                            : KhataFilter.payable;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Net Position Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? colors.surfaceContainerLow : colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color:
                    colors.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.5),
                width: 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  isNetPositive
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 16,
                  color: isNetPositive ? money.receivable : money.payable,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isNetPositive
                        ? 'Net Position: You have +@amount to receive'.trParams(<String, String>{
                            'amount': AppFormatters.money(net),
                          })
                        : 'Net Position: You have -@amount to pay'.trParams(<String, String>{
                            'amount': AppFormatters.money(net.abs()),
                          }),
                    style: text.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _SearchAndFilter extends GetView<ContactController> {
  const _SearchAndFilter();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final FinanceColors money = FinanceColors.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Modern Search Field
        Container(
          decoration: BoxDecoration(
            color: isDark ? colors.surfaceContainerLow : colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
              width: 1,
            ),
          ),
          child: Obx(
            () => TextField(
              onChanged: (String v) => controller.searchText.value = v,
              decoration: InputDecoration(
                hintText: 'Search name, mobile or notes...'.tr,
                hintStyle: TextStyle(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: colors.onSurfaceVariant,
                  size: 20,
                ),
                suffixIcon: controller.searchText.value.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => controller.searchText.value = '',
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Filter Pills
        Obx(() {
          Widget filterPill({
            required String label,
            required KhataFilter filter,
            required int count,
            Color? activeColor,
          }) {
            final bool isSelected = controller.filter.value == filter;

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: isSelected
                    ? (isDark ? colors.primaryContainer : colors.primary)
                    : (isDark ? colors.surfaceContainerLow : colors.surface),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  side: BorderSide(
                    color: isSelected
                        ? Colors.transparent
                        : colors.outlineVariant
                            .withValues(alpha: isDark ? 0.3 : 0.6),
                    width: 1,
                  ),
                ),
                child: InkWell(
                  onTap: () => controller.filter.value = filter,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6.5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: isSelected
                                ? (isDark
                                    ? colors.onPrimaryContainer
                                    : colors.onPrimary)
                                : colors.onSurface,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDark
                                    ? colors.primary.withValues(alpha: 0.3)
                                    : Colors.white.withValues(alpha: 0.25))
                                : (activeColor ?? colors.onSurfaceVariant)
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? (isDark
                                      ? colors.onPrimaryContainer
                                      : colors.onPrimary)
                                  : (activeColor ?? colors.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: <Widget>[
                filterPill(
                  label: 'All'.tr,
                  filter: KhataFilter.all,
                  count: controller.allCount,
                ),
                filterPill(
                  label: 'You will get'.tr,
                  filter: KhataFilter.receivable,
                  count: controller.receivableCount,
                  activeColor: money.receivable,
                ),
                filterPill(
                  label: 'You will give'.tr,
                  filter: KhataFilter.payable,
                  count: controller.payableCount,
                  activeColor: money.payable,
                ),
                filterPill(
                  label: 'Settled'.tr,
                  filter: KhataFilter.settled,
                  count: controller.settledCount,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
