import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/features/contacts/views/contact_picker_sheet.dart';
import 'package:finance_tracker/features/notifications/widgets/notification_permission_banner.dart';
import 'package:finance_tracker/features/reminders/controllers/reminder_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Add a reminder, or edit the one passed in [ReminderFormArgs.existing].
class ReminderFormView extends StatefulWidget {
  const ReminderFormView({super.key});

  @override
  State<ReminderFormView> createState() => _ReminderFormViewState();
}

class _ReminderFormViewState extends State<ReminderFormView> {
  final ReminderController _controller = Get.find<ReminderController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _amount = TextEditingController();

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = ReminderController.newId();
  late final ReminderFormArgs _args;
  late ReminderType _type;
  String? _contactId;
  late DateTime _date;
  late TimeOfDay _time;
  ReminderRepeat _repeat = ReminderRepeat.none;
  bool _notify = true;
  String? _whenError;
  String? _contactError;

  Reminder? get _existing => _args.existing;
  bool get _editing => _existing != null;

  @override
  void initState() {
    super.initState();
    final Object? raw = Get.arguments;
    _args = raw is ReminderFormArgs ? raw : const ReminderFormArgs();
    final Reminder? r = _existing;
    final DateTime start =
        r?.remindAt ?? DateTime.now().add(const Duration(hours: 1));
    _date = DateTime(start.year, start.month, start.day);
    _time = TimeOfDay(hour: start.hour, minute: start.minute);
    _type = r?.type ?? _args.type;
    _title.text = r?.title ?? _args.title ?? '';
    _description.text = r?.description ?? '';
    final Decimal? amount = r?.amount ?? _args.amount;
    _amount.text = amount?.toString() ?? '';
    _contactId = r?.contactId ?? _args.contactId;
    _repeat = r?.repeat ?? ReminderRepeat.none;
    _notify = r?.notificationEnabled ?? true;
    _controller.save.error.value = null;
    _controller.deletion.error.value = null;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  DateTime get _remindAt =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _chooseContact() async {
    final Contact? picked = await pickContact();
    if (picked == null) return;
    setState(() {
      _contactId = picked.id;
      _contactError = null;
    });
  }

  Future<void> _submit() async {
    final bool valid = _formKey.currentState?.validate() ?? false;
    final DateTime remindAt = _remindAt;
    // A time in the past could never alert. Editing without moving the time
    // is allowed, so an overdue reminder can still be corrected.
    final bool moved = _existing == null || _existing!.remindAt != remindAt;
    final String? whenError = moved && !remindAt.isAfter(DateTime.now())
        ? 'Pick a date and time in the future'
        : null;
    final String? contactError = _type.involvesContact && _contactId == null
        ? 'Choose who this is about'
        : null;
    setState(() {
      _whenError = whenError;
      _contactError = contactError;
    });
    if (!valid || whenError != null || contactError != null) return;

    final String description = _description.text.trim();
    final String amount = _amount.text.trim();
    final bool saved = await _controller.saveReminder(
      id: _existing?.id ?? _id,
      existing: _existing,
      type: _type,
      title: _title.text.trim(),
      description: description.isEmpty ? null : description,
      amount: amount.isEmpty ? null : Decimal.parse(amount),
      contactId: _contactId,
      transactionId: _existing?.transactionId ?? _args.transactionId,
      remindAt: remindAt,
      repeat: _repeat,
      notificationEnabled: _notify,
    );
    if (!saved) return;
    AppSnackbar.show(_editing ? 'Reminder updated' : 'Reminder added');
    Get.back<void>();
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmDestructive(
      context,
      title: 'Delete this reminder?',
      message: 'It will no longer alert you.',
    );
    if (!confirmed) return;
    if (await _controller.deleteReminder(_existing!.id)) {
      AppSnackbar.show('Reminder deleted');
      // Past the detail screen, which no longer has a reminder to show.
      Get.back<void>();
      Get.back<void>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final DateTime today = DateTime.now();
    final DateTime todayDay = DateTime(today.year, today.month, today.day);
    final String? contactName = _controller.contactName(_contactId);

    return Scaffold(
      appBar: AppAppBar(title: _editing ? 'Edit reminder' : 'Add reminder'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 120,
          child: Form(
            key: _formKey,
            child: ListView(
              children: <Widget>[
                if (_notify) const NotificationPermissionBanner(),
                Text('Type', style: text.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final ReminderType t in ReminderType.values)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Title',
                  controller: _title,
                  autofocus: !_editing,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      Validators.requiredField(v, 'title'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                if (_type.hasAmount) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    autovalidateMode: AutovalidateMode.onUserInteractionIfError,
                    validator: (String? v) => (v ?? '').trim().isEmpty
                        ? null
                        : Validators.positiveAmount(v),
                    decoration: const InputDecoration(
                      labelText: 'Amount (optional)',
                      prefixText: '₹ ',
                      hintText: '0.00',
                    ),
                  ),
                ],
                if (_type.involvesContact) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: _chooseContact,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Contact',
                        errorText: _contactError,
                        suffixIcon: const Icon(Icons.person_search_outlined),
                      ),
                      child: Text(
                        contactName ??
                            (_contactId == null
                                ? 'Choose a contact'
                                : 'Contact'),
                        style: text.bodyLarge,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: AppDateField(
                        label: 'Date',
                        value: _date,
                        firstDate: _date.isBefore(todayDay) ? _date : todayDay,
                        onChanged: (DateTime d) => setState(() => _date = d),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppTimeField(
                        label: 'Time',
                        value: _time,
                        onChanged: (TimeOfDay t) => setState(() => _time = t),
                      ),
                    ),
                  ],
                ),
                if (_whenError != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _whenError!,
                    style: text.bodySmall?.copyWith(color: colors.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<ReminderRepeat>(
                  initialValue: _repeat,
                  decoration: const InputDecoration(labelText: 'Repeat'),
                  items: <DropdownMenuItem<ReminderRepeat>>[
                    for (final ReminderRepeat r in ReminderRepeat.values)
                      DropdownMenuItem<ReminderRepeat>(
                        value: r,
                        child: Text(r.label),
                      ),
                  ],
                  onChanged: (ReminderRepeat? v) =>
                      setState(() => _repeat = v ?? _repeat),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Notify me'),
                  subtitle: const Text('Show a notification at this time'),
                  value: _notify,
                  onChanged: (bool v) => setState(() => _notify = v),
                ),
                const SizedBox(height: AppSpacing.md),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: _editing ? 'Save changes' : 'Save',
                    icon: Icons.check_rounded,
                    isLoading: _controller.save.isBusy.value,
                    onPressed: _submit,
                  ),
                ),
                if (_editing) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  SubmitErrorMessage(_controller.deletion),
                  Obx(
                    () => AppButton(
                      label: 'Delete reminder',
                      icon: Icons.delete_outline,
                      variant: AppButtonVariant.destructive,
                      isLoading: _controller.deletion.isBusy.value,
                      onPressed: _delete,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
