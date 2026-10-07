import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/widgets/contact_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void openAddContact() => Get.toNamed<void>(AppRoutes.contactForm);

/// Standalone khata route (back-navigable from the dashboard).
class ContactListView extends StatelessWidget {
  const ContactListView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppAppBar(title: 'Khata'),
      body: SafeArea(child: ContactListContent()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openAddContact,
        icon: Icon(Icons.person_add_alt_1_outlined),
        label: Text('Add contact'),
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
        return const AppContent(child: SkeletonList());
      }
      final String? error = controller.error.value;
      if (error != null && !controller.hasContacts) {
        return ErrorState(message: error, onRetry: controller.load);
      }
      if (!controller.hasContacts) {
        return const EmptyState(
          icon: Icons.people_outline,
          title: 'No contacts yet',
          message:
              'Add the people you lend to or borrow from, then record credit '
              'and debit entries against them.',
          actionLabel: 'Add contact',
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
              if (rows.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matching contacts',
                    message: 'Try a different name or filter.',
                  ),
                )
              else
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (BuildContext context, int index) =>
                      ContactBalanceTile(
                        row: rows[index],
                        onTap: () => Get.toNamed<void>(
                          AppRoutes.contactDetail,
                          arguments: rows[index].contact.id,
                        ),
                      ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
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
    final FinanceColors money = FinanceColors.of(context);
    return Obx(
      () => Row(
        children: <Widget>[
          Expanded(
            child: SummaryTile(
              icon: Icons.call_received_rounded,
              label: 'You will get',
              value: AppFormatters.money(controller.summary.value.receivable),
              color: money.receivable,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: SummaryTile(
              icon: Icons.call_made_rounded,
              label: 'You will give',
              value: AppFormatters.money(controller.summary.value.payable),
              color: money.payable,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAndFilter extends GetView<ContactController> {
  const _SearchAndFilter();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          onChanged: (String v) => controller.searchText.value = v,
          decoration: const InputDecoration(
            hintText: 'Search name or mobile',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(
          () => Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              for (final (KhataFilter f, String label)
                  in <(KhataFilter, String)>[
                    (KhataFilter.all, 'All'),
                    (KhataFilter.receivable, 'You will get'),
                    (KhataFilter.payable, 'You will give'),
                  ])
                ChoiceChip(
                  label: Text(label),
                  selected: controller.filter.value == f,
                  onSelected: (_) => controller.filter.value = f,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
