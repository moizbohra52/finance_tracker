import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:get/get.dart';

/// Represents normalized contact information imported or selected from the device.
class DeviceContactData {
  const DeviceContactData({
    required this.id,
    required this.displayName,
    this.phones = const <String>[],
    this.email,
    this.address,
    this.notes,
  });

  final String id;
  final String displayName;
  final List<String> phones;
  final String? email;
  final String? address;
  final String? notes;

  /// Returns true if this contact has at least one phone number.
  bool get hasPhone => phones.isNotEmpty;

  /// Returns true if this contact has multiple phone numbers.
  bool get hasMultiplePhones => phones.length > 1;

  /// Primary phone number or null.
  String? get primaryPhone => phones.isNotEmpty ? phones.first : null;
}

/// Service that accesses device contacts, requests runtime permissions, and
/// provides search/filtering for Khata autofill.
class DeviceContactsService {
  DeviceContactsService._();
  static final DeviceContactsService instance = DeviceContactsService._();

  List<DeviceContactData>? _cachedContacts;
  bool _isLoading = false;

  /// Whether reading contacts is supported on the current platform.
  bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Checks if contacts permission is already granted.
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    try {
      return await fc.FlutterContacts.permissions.has(fc.PermissionType.read);
    } catch (_) {
      return false;
    }
  }

  /// Requests permission to read device contacts.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      final fc.PermissionStatus status = await fc.FlutterContacts.permissions
          .request(fc.PermissionType.read);
      return status == fc.PermissionStatus.granted ||
          status == fc.PermissionStatus.limited;
    } catch (_) {
      return false;
    }
  }

  /// Opens the app settings if permission is permanently denied.
  Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await fc.FlutterContacts.permissions.openSettings();
    } catch (_) {}
  }

  /// Clears the cached contacts so next load fetches fresh data.
  void clearCache() {
    _cachedContacts = null;
  }

  /// Loads contacts from the device phonebook.
  Future<List<DeviceContactData>> loadContacts({
    bool forceRefresh = false,
  }) async {
    if (!isSupported) return <DeviceContactData>[];
    if (!forceRefresh && _cachedContacts != null) {
      return _cachedContacts!;
    }
    if (_isLoading) {
      return _cachedContacts ?? <DeviceContactData>[];
    }

    _isLoading = true;
    try {
      final bool granted = await hasPermission();
      if (!granted) {
        final bool requested = await requestPermission();
        if (!requested) {
          return <DeviceContactData>[];
        }
      }

      final List<fc.Contact> rawList = await fc.FlutterContacts.getAll(
        properties: <fc.ContactProperty>{
          fc.ContactProperty.name,
          fc.ContactProperty.phone,
          fc.ContactProperty.email,
          fc.ContactProperty.address,
          fc.ContactProperty.note,
          fc.ContactProperty.organization,
        },
      );

      final List<DeviceContactData> mapped = <DeviceContactData>[];
      for (final fc.Contact c in rawList) {
        final String name = (c.displayName ?? '').trim();
        final List<String> phones = c.phones
            .map((fc.Phone p) => p.number.trim())
            .where((String s) => s.isNotEmpty)
            .toSet()
            .toList();

        if (name.isEmpty && phones.isEmpty) continue;

        final String? email = c.emails.isNotEmpty
            ? c.emails.first.address.trim()
            : null;

        String? address;
        if (c.addresses.isNotEmpty) {
          final fc.Address a = c.addresses.first;
          final String? formatted = a.formatted?.trim();
          if (formatted != null && formatted.isNotEmpty) {
            address = formatted;
          } else {
            final List<String> parts =
                <String?>[a.street, a.city, a.state, a.postalCode, a.country]
                    .where((String? s) => s != null && s.trim().isNotEmpty)
                    .map((String? s) => s!.trim())
                    .toList();
            if (parts.isNotEmpty) {
              address = parts.join(', ');
            }
          }
        }

        String? notes;
        if (c.notes.isNotEmpty && c.notes.first.note.trim().isNotEmpty) {
          notes = c.notes.first.note.trim();
        } else if (c.organizations.isNotEmpty &&
            c.organizations.first.name != null &&
            c.organizations.first.name!.trim().isNotEmpty) {
          notes = c.organizations.first.name!.trim();
        }

        mapped.add(
          DeviceContactData(
            id: c.id ?? '',
            displayName: name.isNotEmpty
                ? name
                : (phones.isNotEmpty ? phones.first : 'Unnamed Contact'.tr),
            phones: phones,
            email: email,
            address: address,
            notes: notes,
          ),
        );
      }

      mapped.sort(
        (DeviceContactData a, DeviceContactData b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

      _cachedContacts = mapped;
      return mapped;
    } catch (_) {
      return <DeviceContactData>[];
    } finally {
      _isLoading = false;
    }
  }

  /// Searches contacts by name or phone digits.
  Future<List<DeviceContactData>> searchContacts(String query) async {
    final List<DeviceContactData> all = await loadContacts();
    final String clean = query.trim().toLowerCase();
    if (clean.isEmpty) {
      return all.take(20).toList();
    }

    final String digits = clean.replaceAll(RegExp(r'[^0-9]'), '');

    final List<DeviceContactData> matched = <DeviceContactData>[];
    for (final DeviceContactData c in all) {
      final bool nameMatches = c.displayName.toLowerCase().contains(clean);
      bool phoneMatches = false;
      if (digits.isNotEmpty) {
        phoneMatches = c.phones.any(
          (String p) => p.replaceAll(RegExp(r'[^0-9]'), '').contains(digits),
        );
      } else {
        phoneMatches = c.phones.any(
          (String p) => p.toLowerCase().contains(clean),
        );
      }

      if (nameMatches || phoneMatches) {
        matched.add(c);
        if (matched.length >= 25) break;
      }
    }
    return matched;
  }

  /// Opens the native system contact picker directly.
  Future<DeviceContactData?> pickFromSystemPicker() async {
    if (!isSupported) return null;
    try {
      final fc.Contact? picked = await fc.FlutterContacts.native.showPicker(
        properties: <fc.ContactProperty>{
          fc.ContactProperty.name,
          fc.ContactProperty.phone,
          fc.ContactProperty.email,
          fc.ContactProperty.address,
          fc.ContactProperty.note,
          fc.ContactProperty.organization,
        },
      );
      if (picked == null) return null;

      final String name = (picked.displayName ?? '').trim();
      final List<String> phones = picked.phones
          .map((fc.Phone p) => p.number.trim())
          .where((String s) => s.isNotEmpty)
          .toSet()
          .toList();

      final String? email = picked.emails.isNotEmpty
          ? picked.emails.first.address.trim()
          : null;

      String? address;
      if (picked.addresses.isNotEmpty) {
        address = picked.addresses.first.formatted?.trim();
      }

      String? notes;
      if (picked.notes.isNotEmpty &&
          picked.notes.first.note.trim().isNotEmpty) {
        notes = picked.notes.first.note.trim();
      } else if (picked.organizations.isNotEmpty &&
          picked.organizations.first.name != null &&
          picked.organizations.first.name!.trim().isNotEmpty) {
        notes = picked.organizations.first.name!.trim();
      }

      return DeviceContactData(
        id: picked.id ?? '',
        displayName: name.isNotEmpty
            ? name
            : (phones.isNotEmpty ? phones.first : 'Unnamed Contact'.tr),
        phones: phones,
        email: email,
        address: address,
        notes: notes,
      );
    } catch (_) {
      return null;
    }
  }
}
