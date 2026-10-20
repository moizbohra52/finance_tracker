import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/features/contacts/services/device_contacts_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shows a bottom sheet allowing the user to search and pick a contact from their device.
Future<DeviceContactData?> showDeviceContactPicker(BuildContext context) {
  return showModalBottomSheet<DeviceContactData>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.lg),
      ),
    ),
    builder: (BuildContext context) => const DeviceContactPickerSheet(),
  );
}

class DeviceContactPickerSheet extends StatefulWidget {
  const DeviceContactPickerSheet({super.key});

  @override
  State<DeviceContactPickerSheet> createState() =>
      _DeviceContactPickerSheetState();
}

class _DeviceContactPickerSheetState extends State<DeviceContactPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final DeviceContactsService _service = DeviceContactsService.instance;

  bool _isLoading = true;
  bool _hasPermission = false;
  String? _errorMessage;
  List<DeviceContactData> _allContacts = <DeviceContactData>[];
  List<DeviceContactData> _filteredContacts = <DeviceContactData>[];

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkAndLoad() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (!_service.isSupported) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Contact access is not supported on this device/platform.';
      });
      return;
    }

    final bool permitted = await _service.hasPermission();
    if (!permitted) {
      final bool requested = await _service.requestPermission();
      if (!requested) {
        setState(() {
          _isLoading = false;
          _hasPermission = false;
        });
        return;
      }
    }

    final List<DeviceContactData> loaded = await _service.loadContacts();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasPermission = true;
        _allContacts = loaded;
        _filteredContacts = loaded;
      });
    }
  }

  void _onSearchChanged(String query) {
    final String clean = query.trim().toLowerCase();
    if (clean.isEmpty) {
      setState(() => _filteredContacts = _allContacts);
      return;
    }

    final String digits = clean.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() {
      _filteredContacts = _allContacts.where((DeviceContactData c) {
        final bool nameMatch = c.displayName.toLowerCase().contains(clean);
        bool phoneMatch = false;
        if (digits.isNotEmpty) {
          phoneMatch = c.phones.any(
            (String p) => p.replaceAll(RegExp(r'[^0-9]'), '').contains(digits),
          );
        } else {
          phoneMatch = c.phones.any(
            (String p) => p.toLowerCase().contains(clean),
          );
        }
        return nameMatch || phoneMatch;
      }).toList();
    });
  }

  Future<void> _pickNative() async {
    final DeviceContactData? picked = await _service.pickFromSystemPicker();
    if (picked != null && mounted) {
      Get.back<DeviceContactData>(result: picked);
    }
  }

  Widget _buildAvatar(DeviceContactData contact, ColorScheme colors) {
    final String initial = contact.displayName.trim().isNotEmpty
        ? contact.displayName.trim().substring(0, 1).toUpperCase()
        : '?';

    return CircleAvatar(
      radius: 20,
      backgroundColor: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
      child: Text(
        initial,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final double sheetHeight = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: sheetHeight),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.contacts_rounded, size: 22),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Select from Phone Contacts',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open system contact picker',
                      icon: const Icon(Icons.open_in_new_rounded),
                      onPressed: _pickNative,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Get.back<DeviceContactData>(),
                    ),
                  ],
                ),
              ),

              // Search Bar
              if (_hasPermission && _errorMessage == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      hintText: 'Search by name or number...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.sm,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),

              const Divider(height: AppSpacing.sm),

              // Content Body
              Expanded(
                child: Builder(
                  builder: (BuildContext context) {
                    if (_isLoading) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            CircularProgressIndicator(),
                            SizedBox(height: AppSpacing.md),
                            Text('Loading contacts...'),
                          ],
                        ),
                      );
                    }

                    if (_errorMessage != null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 48,
                                color: colors.error,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: text.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (!_hasPermission) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.no_accounts_outlined,
                                size: 48,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'Permission Required',
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Please allow Track Day to read your contacts to auto-fill customer and vendor details into Khata.',
                                textAlign: TextAlign.center,
                                style: text.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              AppButton(
                                label: 'Grant Permission',
                                icon: Icons.lock_open_rounded,
                                onPressed: _checkAndLoad,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              TextButton(
                                onPressed: _service.openSettings,
                                child: const Text('Open App Settings'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (_filteredContacts.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.search_off_rounded,
                                size: 44,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                _allContacts.isEmpty
                                    ? 'No contacts found on your phone.'
                                    : 'No contacts matching your search.',
                                textAlign: TextAlign.center,
                                style: text.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              if (_allContacts.isNotEmpty) ...<Widget>[
                                const SizedBox(height: AppSpacing.sm),
                                TextButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                  },
                                  child: const Text('Clear search'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      itemCount: _filteredContacts.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final DeviceContactData contact =
                            _filteredContacts[index];
                        final bool hasMulti = contact.hasMultiplePhones;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          leading: _buildAvatar(contact, colors),
                          title: Text(
                            contact.displayName,
                            style: text.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (contact.phones.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 2),
                                Row(
                                  children: <Widget>[
                                    Icon(
                                      Icons.phone_outlined,
                                      size: 13,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        contact.phones.join(' • '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.bodySmall?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    if (hasMulti)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.secondaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${contact.phones.length} numbers',
                                          style: text.labelSmall?.copyWith(
                                            color:
                                                colors.onSecondaryContainer,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              if (contact.email != null &&
                                  contact.email!.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 1),
                                Row(
                                  children: <Widget>[
                                    Icon(
                                      Icons.email_outlined,
                                      size: 13,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        contact.email!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.bodySmall?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: colors.onSurfaceVariant,
                          ),
                          onTap: () =>
                              Get.back<DeviceContactData>(result: contact),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
