import 'package:decimal/decimal.dart';
import 'package:get/get.dart';

/// Form field validators. Each returns an error message, or null when valid.
abstract final class Validators {
  static const int minPasswordLength = 8;

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _letter = RegExp('[A-Za-z]');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _mobile = RegExp(r'^\+?[0-9][0-9 -]{6,18}[0-9]$');

  /// handle@bank. Mirrors the user_settings.upi_id CHECK in Supabase.
  static final RegExp _upiId = RegExp(
    r'^[a-zA-Z0-9._-]{2,256}@[a-zA-Z]{2,64}$',
  );

  static String? requiredField(String? value, String fieldName) =>
      (value == null || value.trim().isEmpty)
      ? 'Enter your @field'.trParams(<String, String>{'field': fieldName})
      : null;

  static String? email(String? value) {
    final String email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email'.tr;
    if (!_email.hasMatch(email)) return 'Enter a valid email address'.tr;
    return null;
  }

  /// Policy for new passwords. Mirrors the server settings in
  /// supabase/config.toml (minimum_password_length, password_requirements).
  static String? newPassword(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'Enter a password'.tr;
    if (password.length < minPasswordLength) {
      return 'Use at least @count characters'.trParams(<String, String>{
        'count': '$minPasswordLength',
      });
    }
    if (!_letter.hasMatch(password) || !_digit.hasMatch(password)) {
      return 'Use both letters and numbers'.tr;
    }
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() password) {
    return (String? value) {
      if (value == null || value.isEmpty) return 'Confirm your password'.tr;
      return value == password() ? null : 'Passwords do not match'.tr;
    };
  }

  static String? optionalMobile(String? value) {
    final String mobile = value?.trim() ?? '';
    if (mobile.isEmpty) return null;
    final Iterable<String> parts = mobile
        .split(RegExp(r'[,;]'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty);
    if (parts.isEmpty) return null;
    for (final String part in parts) {
      if (!_mobile.hasMatch(part)) {
        return 'Enter a valid mobile number'.tr;
      }
    }
    return null;
  }

  static final RegExp _amount = RegExp(r'^\d{1,13}(\.\d{1,2})?$');

  /// A positive money amount with at most two decimals.
  static String? optionalUpiId(String? value) {
    final String upiId = value?.trim() ?? '';
    if (upiId.isEmpty) return null;
    return _upiId.hasMatch(upiId) ? null : 'Enter a UPI ID like name@bank'.tr;
  }

  static String? positiveAmount(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter an amount'.tr;
    final Decimal? parsed = _amount.hasMatch(text)
        ? Decimal.tryParse(text)
        : null;
    if (parsed == null) return 'Enter a valid amount, e.g. 250.50'.tr;
    return parsed > Decimal.zero ? null : 'Amount must be more than zero'.tr;
  }

  /// A money amount with at most two decimals; zero is allowed.
  static String? nonNegativeAmount(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter an amount (0 if none)'.tr;
    return _amount.hasMatch(text)
        ? null
        : 'Enter a valid amount, e.g. 250.50'.tr;
  }

  static String? name(String? value, String fieldName) =>
      (value == null || value.trim().isEmpty)
      ? 'Enter @field'.trParams(<String, String>{'field': fieldName})
      : null;

  static const int maxNameLength = 80;
  static final RegExp _personName = RegExp(
    r"^[\p{L}\p{M}][\p{L}\p{M} .'-]*$",
    unicode: true,
  );

  /// The account holder's name: required, at most [maxNameLength] characters,
  /// letters in any script plus spaces, dots, apostrophes and hyphens.
  static String? profileName(String? value) {
    final String name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter your name'.tr;
    if (name.length > maxNameLength) {
      return 'Keep your name under @count characters'.trParams(<String, String>{
        'count': '$maxNameLength',
      });
    }
    return _personName.hasMatch(name)
        ? null
        : 'Use letters, spaces, dots, apostrophes or hyphens only'.tr;
  }
}
