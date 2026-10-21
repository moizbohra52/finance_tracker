import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_detail_controller.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/features/contacts/views/contact_entry_view.dart';
import 'package:finance_tracker/features/contacts/views/send_reminder_sheet.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ContactDetailView extends GetView<ContactDetailController> {
  const ContactDetailView({super.key, required this.id});

  /// Tag of this screen's controller (see routeIdArgument).
  final String id;

  @override
  String get tag => id;

  Future<void> _delete(BuildContext context, Contact contact) async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete @name?'.trParams(<String, String>{'name': contact.name}),
      message:
          'The contact and their ledger entries will be removed from your khata.'
              .tr,
    );
    if (!confirmed) return;
    if (await controller.deleteContact()) {
      AppSnackbar.show('Contact deleted'.tr);
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final Contact? contact = controller.contact.value;
      return Scaffold(
        appBar: AppAppBar(
          title: contact?.name ?? 'Contact'.tr,
          actions: <Widget>[
            if (contact != null) ...<Widget>[
              IconButton(
                tooltip: 'Send reminder via WhatsApp / SMS'.tr,
                icon: const Icon(Icons.send_rounded),
                onPressed: () => SendReminderSheet.show(
                  context,
                  contact: contact,
                  balance: controller.balance.value,
                ),
              ),
              IconButton(
                tooltip: 'Add reminder'.tr,
                icon: const Icon(Icons.alarm_add_outlined),
                onPressed: () => Get.toNamed<void>(
                  AppRoutes.reminderForm,
                  arguments: ReminderFormArgs.forContact(
                    contactId: contact.id,
                    balance: controller.balance.value,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit contact'.tr,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Get.toNamed<void>(
                  AppRoutes.contactForm,
                  arguments: contact,
                ),
              ),
              IconButton(
                tooltip: 'Delete contact'.tr,
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
      return LoadingState(message: 'Loading contact'.tr);
    }
    final String? error = controller.error.value;
    if (error != null) {
      return ErrorState(message: error, onRetry: controller.load);
    }
    if (contact == null) {
      return EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Contact not found'.tr,
        message: 'It may have been deleted.'.tr,
      );
    }
    return AppContent(
      child: RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          children: <Widget>[
            _BalanceHeader(contact: contact, id: id),
            const SizedBox(height: AppSpacing.md),
            _EntryActions(contact: contact),
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(title: 'Ledger'.tr),
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
              AppCard(
                child: EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'No entries yet'.tr,
                  message: 'Add a credit or debit to start this ledger.'.tr,
                ),
              )
            else
              AppListCard(
                children: <Widget>[
                  for (final ContactTransaction e in controller.entries)
                    _EntryTile(entry: e, id: id),
                ],
              ),
            const SizedBox(height: AppSpacing.lg),
            _ContactInfo(contact: contact, balance: controller.balance.value),
          ],
        ),
      ),
    );
  }
}

class _BalanceHeader extends GetView<ContactDetailController> {
  const _BalanceHeader({required this.contact, required this.id});

  final String id;

  @override
  String get tag => id;

  final Contact contact;

  Future<void> _shareStatement() async {
    if (await controller.shareStatement()) return;
    final String? error = controller.statement.error.value;
    if (error != null) AppSnackbar.show(error);
  }

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
            IconBadge.initial(contact.name, size: AppSizes.iconLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              receivable
                  ? 'You will get'.tr
                  : (payable ? 'You will give'.tr : 'All settled'.tr),
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
            if (balance != Decimal.zero) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text('Send Reminder (WhatsApp / SMS)'.tr),
                onPressed: () => SendReminderSheet.show(
                  context,
                  contact: contact,
                  balance: balance,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text('Share statement (PDF)'.tr),
              onPressed: controller.statement.isBusy.value
                  ? null
                  : _shareStatement,
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
                label: 'Add credit'.tr,
                icon: Icons.add_card_outlined,
                onPressed: () => _add(ContactTransactionType.credit),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                label: 'Add debit'.tr,
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
              child: Text('Payment received'.tr),
            ),
            TextButton(
              onPressed: () => _add(ContactTransactionType.paymentMade),
              child: Text('Payment made'.tr),
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
  const _EntryTile({required this.entry, required this.id});

  final String id;
  final ContactTransaction entry;

  @override
  String get tag => id;

  void _edit() {
    Get.toNamed<void>(
      AppRoutes.contactEntry,
      arguments: ContactEntryArgs(
        contactId: entry.contactId,
        contactName: controller.contact.value?.name,
        type: entry.type,
        existing: entry,
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete entry?'.tr,
      message: '@entry of @amount will be removed.'.trParams(<String, String>{
        'entry': contactEntryLabel(entry.type),
        'amount': AppFormatters.money(entry.amount),
      }),
    );
    if (confirmed && await controller.deleteEntry(entry.id)) {
      AppSnackbar.show('Entry deleted'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool raises = _raisesBalance(entry.type);
    final Color color = raises ? money.receivable : money.payable;
    final String note = entry.note ?? '';
    final String due = entry.dueDate == null
        ? ''
        : ' · ${'Due @date'.trParams(<String, String>{'date': AppFormatters.date(entry.dueDate!)})}';
    return AppListTile(
      onTap: _edit,
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      leading: IconBadge(
        icon: raises ? Icons.call_received_rounded : Icons.call_made_rounded,
        color: color,
      ),
      title: contactEntryLabel(entry.type),
      subtitle:
          '${AppFormatters.dateTime(entry.transactionDate)}$due'
          '${note.isEmpty ? '' : '\n$note'}',
      subtitleMaxLines: 3,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            AppFormatters.signedMoney(entry.amount, positive: raises),
            style: text.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Edit entry'.tr,
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
          IconButton(
            tooltip: 'Delete entry'.tr,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context),
          ),
        ],
      ),
    );
  }
}

class _ContactInfo extends StatelessWidget {
  const _ContactInfo({required this.contact, required this.balance});

  final Contact contact;
  final Decimal balance;

  @override
  Widget build(BuildContext context) {
    final List<(String, String?, bool)> rows = <(String, String?, bool)>[];
    final String? rawMobile = contact.mobile?.trim();
    if (rawMobile != null && rawMobile.isNotEmpty) {
      final List<String> numbers = rawMobile
          .split(RegExp(r'[,;]'))
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
      if (numbers.length > 1) {
        for (int i = 0; i < numbers.length; i++) {
          rows.add((
            'Mobile @number'.trParams(<String, String>{'number': '${i + 1}'}),
            numbers[i],
            true,
          ));
        }
      } else if (numbers.isNotEmpty) {
        rows.add(('Mobile'.tr, numbers.first, true));
      }
    }
    if ((contact.email ?? '').isNotEmpty) {
      rows.add(('Email'.tr, contact.email, false));
    }
    if ((contact.address ?? '').isNotEmpty) {
      rows.add(('Address'.tr, contact.address, false));
    }
    if ((contact.notes ?? '').isNotEmpty) {
      rows.add(('Notes'.tr, contact.notes, false));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: 'Details'.tr),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            children: <Widget>[
              for (final (String, String?, bool) r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 80,
                        child: Text(r.$1, style: text.bodyMedium),
                      ),
                      Expanded(child: Text(r.$2!, style: text.titleSmall)),
                      if (r.$3)
                        IconButton(
                          tooltip: 'Send reminder via WhatsApp'.tr,
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 20,
                            color: Color(0xFF25D366),
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => SendReminderSheet.show(
                            context,
                            contact: contact,
                            balance: balance,
                          ),
                        ),
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
