import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_detail_controller.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/features/contacts/views/contact_entry_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ContactDetailView extends GetView<ContactDetailController> {
  const ContactDetailView({super.key});

  Future<void> _delete(BuildContext context, Contact contact) async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete ${contact.name}?',
      message:
          'The contact and their ledger entries will be removed from your '
          'khata.',
    );
    if (!confirmed) return;
    if (await controller.deleteContact()) {
      AppSnackbar.show('Contact deleted');
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final Contact? contact = controller.contact.value;
      return Scaffold(
        appBar: AppAppBar(
          title: contact?.name ?? 'Contact',
          actions: <Widget>[
            if (contact != null) ...<Widget>[
              IconButton(
                tooltip: 'Edit contact',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Get.toNamed<void>(
                  AppRoutes.contactForm,
                  arguments: contact,
                ),
              ),
              IconButton(
                tooltip: 'Delete contact',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, contact),
              ),
            ],
          ],
        ),
        body: SafeArea(child: _body(context, contact)),
      );
    });
  }

  Widget _body(BuildContext context, Contact? contact) {
    if (controller.isLoading.value) {
      return const LoadingState(message: 'Loading contact');
    }
    final String? error = controller.error.value;
    if (error != null) {
      return ErrorState(message: error, onRetry: controller.load);
    }
    if (contact == null) {
      return const EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Contact not found',
        message: 'It may have been deleted.',
      );
    }
    return AppContent(
      child: RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          children: <Widget>[
            _BalanceHeader(contact: contact),
            const SizedBox(height: AppSpacing.md),
            _EntryActions(contact: contact),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Ledger'),
            const SizedBox(height: AppSpacing.sm),
            Obx(() {
              final String? deleteError = controller.deletion.error.value;
              return deleteError == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: InlineMessage(message: deleteError),
                    );
            }),
            if (controller.entries.isEmpty)
              const AppCard(
                child: EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'No entries yet',
                  message: 'Add a credit or debit to start this ledger.',
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  children: <Widget>[
                    for (final ContactTransaction e in controller.entries)
                      _EntryTile(entry: e),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            _ContactInfo(contact: contact),
          ],
        ),
      ),
    );
  }
}

class _BalanceHeader extends GetView<ContactDetailController> {
  const _BalanceHeader({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Obx(() {
      final balance = controller.balance.value;
      final bool receivable = balance > Decimal.zero;
      final bool payable = balance < Decimal.zero;
      final Color? color = receivable
          ? money.receivable
          : (payable ? money.payable : null);
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: <Widget>[
            Text(
              receivable
                  ? 'You will get'
                  : (payable ? 'You will give' : 'All settled'),
              style: text.labelLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppFormatters.money(balance.abs()),
              style: text.displaySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _EntryActions extends StatelessWidget {
  const _EntryActions({required this.contact});

  final Contact contact;

  void _add(ContactTransactionType type) => Get.toNamed<void>(
    AppRoutes.contactEntry,
    arguments: ContactEntryArgs(
      contactId: contact.id,
      contactName: contact.name,
      type: type,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                label: 'Add credit',
                icon: Icons.add_card_outlined,
                onPressed: () => _add(ContactTransactionType.credit),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                label: 'Add debit',
                icon: Icons.remove_circle_outline,
                variant: AppButtonVariant.secondary,
                onPressed: () => _add(ContactTransactionType.debit),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextButton(
              onPressed: () => _add(ContactTransactionType.paymentReceived),
              child: const Text('Payment received'),
            ),
            TextButton(
              onPressed: () => _add(ContactTransactionType.paymentMade),
              child: const Text('Payment made'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Whether an entry raises (+) or lowers (−) what the contact owes the user.
bool _raisesBalance(ContactTransactionType t) =>
    t == ContactTransactionType.credit ||
    t == ContactTransactionType.paymentMade ||
    t == ContactTransactionType.adjustment;

class _EntryTile extends GetView<ContactDetailController> {
  const _EntryTile({required this.entry});

  final ContactTransaction entry;

  Future<void> _delete(BuildContext context) async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete entry?',
      message:
          '${contactEntryLabel(entry.type)} of '
          '${AppFormatters.money(entry.amount)} will be removed.',
    );
    if (confirmed && await controller.deleteEntry(entry.id)) {
      AppSnackbar.show('Entry deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool raises = _raisesBalance(entry.type);
    final String note = entry.note ?? '';
    final String due = entry.dueDate == null
        ? ''
        : ' · Due ${AppFormatters.date(entry.dueDate!)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(contactEntryLabel(entry.type)),
      subtitle: Text(
        '${AppFormatters.dateTime(entry.transactionDate)}$due'
        '${note.isEmpty ? '' : '\n$note'}',
        style: text.bodySmall,
      ),
      isThreeLine: note.isNotEmpty,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            AppFormatters.signedMoney(entry.amount, positive: raises),
            style: text.titleSmall?.copyWith(
              color: raises ? money.receivable : money.payable,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Delete entry',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context),
          ),
        ],
      ),
    );
  }
}

class _ContactInfo extends StatelessWidget {
  const _ContactInfo({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final List<(String, String?)> rows = <(String, String?)>[
      ('Mobile', contact.mobile),
      ('Email', contact.email),
      ('Address', contact.address),
      ('Notes', contact.notes),
    ].where(((String, String?) r) => (r.$2 ?? '').isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Details'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            children: <Widget>[
              for (final (String, String?) r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 80,
                        child: Text(r.$1, style: text.bodyMedium),
                      ),
                      Expanded(child: Text(r.$2!, style: text.titleSmall)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
