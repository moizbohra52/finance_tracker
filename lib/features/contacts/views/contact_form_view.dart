import 'dart:async';
import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/features/contacts/services/device_contacts_service.dart';
import 'package:finance_tracker/features/contacts/views/device_contact_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Add a contact, or edit one passed as the route argument.
class ContactFormView extends StatefulWidget {
  const ContactFormView({super.key});

  @override
  State<ContactFormView> createState() => _ContactFormViewState();
}

class _ContactFormViewState extends State<ContactFormView> {
  final ContactFormController _controller = Get.find<ContactFormController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _name = TextEditingController();
  final List<TextEditingController> _mobileControllers =
      <TextEditingController>[];
  final TextEditingController _email = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _opening = TextEditingController(text: '0');

  final FocusNode _nameFocus = FocusNode();
  Timer? _searchDebounce;
  List<DeviceContactData> _suggestions = <DeviceContactData>[];
  bool _showSuggestions = false;

  // One id per form, so a retried save is an idempotent upsert.
  final String _id = ContactFormController.newId();
  late final Contact? _existing;
  String _openingType = 'receivable';

  @override
  void initState() {
    super.initState();
    final Object? args = Get.arguments;
    if (args is Contact) {
      _existing = args;
    } else {
      _existing = null;
    }

    final Contact? c = _existing;
    if (c != null) {
      _name.text = c.name;
      final String? rawMobile = c.mobile?.trim();
      if (rawMobile != null && rawMobile.isNotEmpty) {
        final List<String> parts = rawMobile
            .split(RegExp(r'[,;]'))
            .map((String s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList();
        for (final String p in parts) {
          _mobileControllers.add(TextEditingController(text: p));
        }
      }
      _email.text = c.email ?? '';
      _address.text = c.address ?? '';
      _notes.text = c.notes ?? '';
      _opening.text = c.openingBalance.toString();
      _openingType = c.openingBalanceType;
    } else if (args is Map &&
        args['initialDeviceContact'] is DeviceContactData) {
      final DeviceContactData initial =
          args['initialDeviceContact'] as DeviceContactData;
      _applyDeviceContact(initial, silent: true);
    }

    if (_mobileControllers.isEmpty) {
      _mobileControllers.add(TextEditingController());
    }

    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && mounted) {
        // Small delay to allow tap on suggestion item before closing
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (mounted && !_nameFocus.hasFocus) {
            setState(() => _showSuggestions = false);
          }
        });
      }
    });

    _controller.save.error.value = null;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameFocus.dispose();
    _name.dispose();
    for (final TextEditingController c in _mobileControllers) {
      c.dispose();
    }
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    _opening.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    if (_existing != null) return;
    _searchDebounce?.cancel();
    final String clean = value.trim();
    if (clean.isEmpty) {
      if (mounted) {
        setState(() {
          _suggestions = <DeviceContactData>[];
          _showSuggestions = false;
        });
      }
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      final List<DeviceContactData> results = await DeviceContactsService
          .instance
          .searchContacts(clean);
      if (mounted && _nameFocus.hasFocus) {
        setState(() {
          _suggestions = results;
          _showSuggestions = results.isNotEmpty;
        });
      }
    });
  }

  void _applyDeviceContact(DeviceContactData contact, {bool silent = false}) {
    _name.text = contact.displayName;

    for (final TextEditingController c in _mobileControllers) {
      c.dispose();
    }
    _mobileControllers.clear();

    if (contact.phones.isNotEmpty) {
      for (final String phone in contact.phones) {
        _mobileControllers.add(TextEditingController(text: phone));
      }
    } else {
      _mobileControllers.add(TextEditingController());
    }

    if (contact.email != null && contact.email!.isNotEmpty) {
      _email.text = contact.email!;
    }
    if (contact.address != null && contact.address!.isNotEmpty) {
      _address.text = contact.address!;
    }
    if (contact.notes != null && contact.notes!.isNotEmpty) {
      _notes.text = contact.notes!;
    }

    setState(() {
      _showSuggestions = false;
      _suggestions = <DeviceContactData>[];
    });

    if (!silent) {
      final int phoneCount = contact.phones.length;
      if (phoneCount > 1) {
        AppSnackbar.show(
          'Filled details from contacts (@count numbers added)'.trParams(
            <String, String>{'count': '$phoneCount'},
          ),
        );
      } else {
        AppSnackbar.show('Filled details from contacts'.tr);
      }
    }
  }

  Future<void> _openDeviceContactPicker() async {
    final DeviceContactData? picked = await showDeviceContactPicker(context);
    if (picked != null && mounted) {
      _applyDeviceContact(picked);
    }
  }

  String? _orNull(TextEditingController c) {
    final String v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  String? _getCombinedMobile() {
    final List<String> numbers = _mobileControllers
        .map((TextEditingController c) => c.text.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    return numbers.isEmpty ? null : numbers.join(', ');
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool saved = await _controller.saveContact(
      id: _existing?.id ?? _id,
      existing: _existing,
      name: _name.text.trim(),
      mobile: _getCombinedMobile(),
      email: _orNull(_email),
      address: _orNull(_address),
      notes: _orNull(_notes),
      openingBalance: Decimal.parse(_opening.text.trim()),
      openingBalanceType: _openingType,
    );
    if (!saved) return;
    AppSnackbar.show(
      _existing == null ? 'Contact added'.tr : 'Contact updated'.tr,
    );
    Get.back<void>();
  }

  Widget _buildSuggestionsBox(ColorScheme colors, TextTheme text, bool isDark) {
    if (!_showSuggestions || _suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: AppShadows.card(colors.shadow, isDark: isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs + 2,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.contacts_rounded, size: 14, color: colors.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Phone contacts suggestions (@count)'.trParams(
                      <String, String>{'count': '${_suggestions.length}'},
                    ),
                    style: text.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _showSuggestions = false),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close_rounded, size: 15),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final DeviceContactData s in _suggestions.take(4))
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 1,
              ),
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: colors.primaryContainer,
                child: Text(
                  s.displayName.isNotEmpty
                      ? s.displayName.substring(0, 1).toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              title: Text(
                s.displayName,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: s.phones.isNotEmpty
                  ? Text(
                      s.hasMultiplePhones
                          ? '@phone (+@count more)'.trParams(<String, String>{
                              'phone': s.phones.first,
                              'count': '${s.phones.length - 1}',
                            })
                          : s.phones.first,
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    )
                  : null,
              trailing: s.hasMultiplePhones
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        '@count numbers'.trParams(<String, String>{
                          'count': '${s.phones.length}',
                        }),
                        style: text.labelSmall?.copyWith(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.north_west_rounded,
                      size: 15,
                      color: colors.primary,
                    ),
              onTap: () => _applyDeviceContact(s),
            ),
          if (_suggestions.length > 4)
            InkWell(
              onTap: _openDeviceContactPicker,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      'View all matches in contact picker'.tr,
                      style: text.labelSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 12,
                      color: colors.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImportBanner(ColorScheme colors, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: InkWell(
          onTap: _openDeviceContactPicker,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.contacts_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Pick from Phone Contacts'.tr,
                        style: text.bodyMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Auto-fill name, all phone numbers & details'.tr,
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileSection(ColorScheme colors, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < _mobileControllers.length; i++) ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  label: _mobileControllers.length > 1
                      ? 'Mobile @number (optional)'.trParams(<String, String>{
                          'number': '${i + 1}',
                        })
                      : 'Mobile (optional)'.tr,
                  controller: _mobileControllers[i],
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: Validators.optionalMobile,
                ),
              ),
              if (_mobileControllers.length > 1) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: IconButton(
                    tooltip: 'Remove this number'.tr,
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      color: colors.error,
                      size: 22,
                    ),
                    onPressed: () {
                      setState(() {
                        final TextEditingController removed = _mobileControllers
                            .removeAt(i);
                        removed.dispose();
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 2,
              ),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () {
              setState(() {
                _mobileControllers.add(TextEditingController());
              });
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Add another mobile number'.tr),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = _existing != null;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppAppBar(
        title: editing ? 'Edit contact'.tr : 'Add contact'.tr,
        actions: <Widget>[
          if (!editing)
            IconButton(
              tooltip: 'Choose from phone contacts'.tr,
              icon: const Icon(Icons.contacts_outlined),
              onPressed: _openDeviceContactPicker,
            ),
        ],
      ),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 120,
          child: Form(
            key: _formKey,
            child: ListView(
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xxl,
              ),
              children: <Widget>[
                if (!editing) _buildImportBanner(colors, text),
                AppTextField(
                  label: 'Name'.tr,
                  controller: _name,
                  autofocus: !editing,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) => Validators.name(v, 'a name'.tr),
                  onChanged: _onNameChanged,
                  suffixIcon: !editing
                      ? IconButton(
                          tooltip: 'Pick from contacts'.tr,
                          icon: const Icon(Icons.contacts_outlined),
                          onPressed: _openDeviceContactPicker,
                        )
                      : null,
                ),
                _buildSuggestionsBox(colors, text, isDark),
                const SizedBox(height: AppSpacing.md),
                _buildMobileSection(colors, text),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Email (optional)'.tr,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      (v ?? '').trim().isEmpty ? null : Validators.email(v),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Address (optional)'.tr,
                  controller: _address,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Notes (optional)'.tr,
                  controller: _notes,
                  minLines: 3,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Opening balance'.tr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<String>(
                  segments: <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'receivable',
                      label: Text('They owe me'.tr),
                    ),
                    ButtonSegment<String>(
                      value: 'payable',
                      label: Text('I owe them'.tr),
                    ),
                  ],
                  selected: <String>{_openingType},
                  onSelectionChanged: (Set<String> s) =>
                      setState(() => _openingType = s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Opening amount'.tr,
                  controller: _opening,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  helperText:
                      'What was already owed before you started here.'.tr,
                  validator: Validators.nonNegativeAmount,
                ),
                const SizedBox(height: AppSpacing.lg),
                SubmitErrorMessage(_controller.save),
                Obx(
                  () => AppButton(
                    label: editing ? 'Save changes'.tr : 'Add contact'.tr,
                    icon: Icons.check_rounded,
                    isLoading: _controller.save.isBusy.value,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
