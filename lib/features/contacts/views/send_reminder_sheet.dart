import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/services/reminder_sender_service.dart';
import 'package:flutter/material.dart';

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

  bool _isEnglish = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _numbers = ReminderSenderService.parsePhoneNumbers(widget.contact.mobile);
    _selectedNumber = _numbers.isNotEmpty ? _numbers.first : '';
    _phoneInputController = TextEditingController(text: _selectedNumber);

    final bool isReceivable = widget.balance >= Decimal.zero;
    final String initialText = ReminderSenderService.buildHinglishMessage(
      contactName: widget.contact.name,
      amount: widget.balance.abs(),
      isReceivable: isReceivable,
      note: widget.customNote,
      upiId: AppFormatters.preferences.upiId,
    );
    _messageController = TextEditingController(text: initialText);
  }

  @override
  void dispose() {
    _phoneInputController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _switchLanguage(bool english) {
    if (_isEnglish == english) return;
    setState(() {
      _isEnglish = english;
      final bool isReceivable = widget.balance >= Decimal.zero;
      final String newText = english
          ? ReminderSenderService.buildEnglishMessage(
              contactName: widget.contact.name,
              amount: widget.balance.abs(),
              isReceivable: isReceivable,
              note: widget.customNote,
              upiId: AppFormatters.preferences.upiId,
            )
          : ReminderSenderService.buildHinglishMessage(
              contactName: widget.contact.name,
              amount: widget.balance.abs(),
              isReceivable: isReceivable,
              note: widget.customNote,
              upiId: AppFormatters.preferences.upiId,
            );
      _messageController.text = newText;
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
      AppSnackbar.show('Please enter a mobile number');
      return;
    }
    final String text = _messageController.text.trim();
    if (text.isEmpty) {
      AppSnackbar.show('Message cannot be empty');
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
        AppSnackbar.show('Opening WhatsApp...');
      case ReminderSendStatus.notInstalled:
        AppSnackbar.show('WhatsApp is not installed on this device.');
      case ReminderSendStatus.noPhone:
        AppSnackbar.show('Invalid phone number for WhatsApp.');
      case ReminderSendStatus.failed:
        AppSnackbar.show('Could not launch WhatsApp. Try SMS or Share.');
    }
  }

  Future<void> _handleSms() async {
    final String phone = _getActivePhone();
    if (phone.isEmpty) {
      AppSnackbar.show('Please enter a mobile number');
      return;
    }
    final String text = _messageController.text.trim();
    if (text.isEmpty) {
      AppSnackbar.show('Message cannot be empty');
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
        AppSnackbar.show('Opening Messaging app...');
      case ReminderSendStatus.noPhone:
        AppSnackbar.show('Invalid phone number for SMS.');
      case ReminderSendStatus.notInstalled || ReminderSendStatus.failed:
        AppSnackbar.show('Could not open Messaging app. Try Share.');
    }
  }

  Future<void> _handleShare() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop();
    await ReminderSenderService.shareGeneral(
      message: text,
      subject: 'Payment reminder for ${widget.contact.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FinanceColors money = FinanceColors.of(context);
    final bool isReceivable = widget.balance >= Decimal.zero;
    final Color balanceColor = isReceivable ? money.receivable : money.payable;
    final String balanceLabel = isReceivable ? 'You will get' : 'You will give';
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
                          'Send Free Reminder',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Direct via WhatsApp or SMS (Zero cost)',
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
                    'Select Mobile Number',
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
                    'Mobile Number (required)',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                TextField(
                  controller: _phoneInputController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.phone_outlined),
                    hintText: 'Enter 10-digit mobile number',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // Language selector chips
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('Message Template', style: theme.textTheme.labelMedium),
                  Row(
                    children: <Widget>[
                      ChoiceChip(
                        label: const Text('Hinglish'),
                        selected: !_isEnglish,
                        onSelected: (bool s) => _switchLanguage(false),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      ChoiceChip(
                        label: const Text('English'),
                        selected: _isEnglish,
                        onSelected: (bool s) => _switchLanguage(true),
                      ),
                    ],
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
                  hintText: 'Type reminder message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  contentPadding: const EdgeInsets.all(AppSpacing.md),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Primary: WhatsApp Send Button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _kWhatsAppColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                onPressed: _isSending ? null : _handleWhatsApp,
                icon: const Icon(Icons.chat_bubble_rounded),
                label: const Text(
                  'Send on WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Secondary: SMS & Share row
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      onPressed: _isSending ? null : _handleSms,
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('Send via SMS'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    onPressed: _isSending ? null : _handleShare,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
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
