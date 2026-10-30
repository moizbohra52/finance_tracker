import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/contacts/services/reminder_sender_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// WhatsApp brand green colour
const Color _kWhatsAppColor = Color(0xFF25D366);

/// Interactive bottom sheet to preview, customize and directly send
/// a reminder via WhatsApp or native SMS for free.
class SendReminderSheet extends StatefulWidget {
  const SendReminderSheet({
    super.key,
    required this.contact,
    required this.balance,
    this.customNote,
  });

  final Contact contact;
  final Decimal balance;
  final String? customNote;

  /// Convenience launcher
  static Future<void> show(
    BuildContext context, {
    required Contact contact,
    required Decimal balance,
    String? customNote,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => SendReminderSheet(
        contact: contact,
        balance: balance,
        customNote: customNote,
      ),
    );
  }

  @override
  State<SendReminderSheet> createState() => _SendReminderSheetState();
}

class _SendReminderSheetState extends State<SendReminderSheet> {
  late final List<String> _numbers;
  late String _selectedNumber;
  late final TextEditingController _phoneInputController;
  late final TextEditingController _messageController;

  AppLanguage _language = AppFormatters.preferences.language;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _numbers = ReminderSenderService.parsePhoneNumbers(widget.contact.mobile);
    _selectedNumber = _numbers.isNotEmpty ? _numbers.first : '';
    _phoneInputController = TextEditingController(text: _selectedNumber);

    _messageController = TextEditingController(text: _message(_language));
  }

  @override
  void dispose() {
    _phoneInputController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _message(AppLanguage language) => ReminderSenderService.buildMessage(
    language,
    contactName: widget.contact.name,
    amount: widget.balance.abs(),
    isReceivable: widget.balance >= Decimal.zero,
    note: widget.customNote,
    upiId: AppFormatters.preferences.upiId,
  );

  void _switchLanguage(AppLanguage language) {
    if (_language == language) return;
    setState(() {
      _language = language;
      _messageController.text = _message(language);
    });
  }

  String _getActivePhone() {
    if (_numbers.isNotEmpty) {
      return _selectedNumber;
    }
    return _phoneInputController.text.trim();
  }

  Future<void> _handleWhatsApp() async {
    final String phone = _getActivePhone();
    if (phone.isEmpty) {
      AppSnackbar.show('Please enter a mobile number'.tr);
      return;
    }
    final String text = _messageController.text.trim();
    if (text.isEmpty) {
      AppSnackbar.show('Message cannot be empty'.tr);
      return;
    }

    setState(() => _isSending = true);
    final ReminderSendStatus status = await ReminderSenderService.sendWhatsApp(
      phone: phone,
      message: text,
    );
    if (!mounted) return;
    setState(() => _isSending = false);

    switch (status) {
      case ReminderSendStatus.success:
        Navigator.of(context).pop();
        AppSnackbar.show('Opening WhatsApp...'.tr);
      case ReminderSendStatus.notInstalled:
        AppSnackbar.show('WhatsApp is not installed on this device.'.tr);
      case ReminderSendStatus.noPhone:
        AppSnackbar.show('Invalid phone number for WhatsApp.'.tr);
      case ReminderSendStatus.failed:
        AppSnackbar.show('Could not launch WhatsApp. Try SMS or Share.'.tr);
    }
  }

  Future<void> _handleSms() async {
    final String phone = _getActivePhone();
    if (phone.isEmpty) {
      AppSnackbar.show('Please enter a mobile number'.tr);
      return;
    }
    final String text = _messageController.text.trim();
    if (text.isEmpty) {
      AppSnackbar.show('Message cannot be empty'.tr);
      return;
    }

    setState(() => _isSending = true);
    final ReminderSendStatus status = await ReminderSenderService.sendSms(
      phone: phone,
      message: text,
    );
    if (!mounted) return;
    setState(() => _isSending = false);

    switch (status) {
      case ReminderSendStatus.success:
        Navigator.of(context).pop();
        AppSnackbar.show('Opening Messaging app...'.tr);
      case ReminderSendStatus.noPhone:
        AppSnackbar.show('Invalid phone number for SMS.'.tr);
      case ReminderSendStatus.notInstalled || ReminderSendStatus.failed:
        AppSnackbar.show('Could not open Messaging app. Try Share.'.tr);
    }
  }

  Future<void> _handleShare() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop();
    await ReminderSenderService.shareGeneral(
      message: text,
      subject: 'Payment reminder for @name'.trParams(<String, String>{
        'name': widget.contact.name,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FinanceColors money = FinanceColors.of(context);
    final bool isReceivable = widget.balance >= Decimal.zero;
    final Color balanceColor = isReceivable ? money.receivable : money.payable;
    final String balanceLabel = isReceivable
        ? 'You will get'.tr
        : 'You will give'.tr;
    final EdgeInsets insets = MediaQuery.of(context).viewInsets;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: AppSpacing.lg + insets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Top drag indicator
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),

              // Title row with Close button
              Row(
                children: <Widget>[
                  IconBadge(
                    icon: Icons.send_rounded,
                    color: theme.colorScheme.primary,
                    size: AppSizes.iconBadgeSmall,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Send Free Reminder'.tr,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Direct via WhatsApp or SMS (Zero cost)'.tr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Contact summary card
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    IconBadge.initial(widget.contact.name, size: 40),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.contact.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            '$balanceLabel ${AppFormatters.money(widget.balance.abs())}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: balanceColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Phone number selector or manual entry
              if (_numbers.length > 1) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    'Select Mobile Number'.tr,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: _numbers.map((String num) {
                    final bool isSelected = _selectedNumber == num;
                    return ChoiceChip(
                      label: Text(num),
                      selected: isSelected,
                      onSelected: (bool selected) {
                        if (selected) setState(() => _selectedNumber = num);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.sm),
              ] else if (_numbers.isEmpty) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    'Mobile Number (required)'.tr,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                TextField(
                  controller: _phoneInputController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.phone_outlined),
                    hintText: 'Enter 10-digit mobile number'.tr,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // Language selector chips, below the label: three do not fit
              // beside it on a phone.
              Text('Message Template'.tr, style: theme.textTheme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                children: <Widget>[
                  for (final AppLanguage language in AppLanguage.values)
                    ChoiceChip(
                      label: Text(language.label),
                      selected: _language == language,
                      onSelected: (bool s) => _switchLanguage(language),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              // Message input box
              TextField(
                controller: _messageController,
                maxLines: 4,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Type reminder message...'.tr,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  contentPadding: const EdgeInsets.all(AppSpacing.md),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Primary: WhatsApp Send Button (brand colours, theme shape)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _kWhatsAppColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isSending ? null : _handleWhatsApp,
                icon: const Icon(Icons.chat_bubble_rounded),
                label: Text('Send on WhatsApp'.tr),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Secondary: SMS & Share row
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSending ? null : _handleSms,
                      icon: const Icon(Icons.sms_outlined),
                      label: Text('Send via SMS'.tr),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _isSending ? null : _handleShare,
                    icon: const Icon(Icons.share_outlined),
                    label: Text('Share'.tr),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
