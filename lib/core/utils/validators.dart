import 'package:decimal/decimal.dart';

/// Form field validators. Each returns an error message, or null when valid.
abstract final class Validators {
  static const int minPasswordLength = 8;

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _letter = RegExp('[A-Za-z]');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _mobile = RegExp(r'^\+?[0-9][0-9 -]{6,18}[0-9]$');

  static String? requiredField(String? value, String fieldName) =>
      (value == null || value.trim().isEmpty) ? 'Enter your $fieldName' : null;

  static String? email(String? value) {
    final String email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  /// Policy for new passwords. Mirrors the server settings in
  /// supabase/config.toml (minimum_password_length, password_requirements).
  static String? newPassword(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'Enter a password';
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    if (!_letter.hasMatch(password) || !_digit.hasMatch(password)) {
      return 'Use both letters and numbers';
    }
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() password) {
    return (String? value) {
      if (value == null || value.isEmpty) return 'Confirm your password';
      return value == password() ? null : 'Passwords do not match';
    };
  }

  static String? optionalMobile(String? value) {
    final String mobile = value?.trim() ?? '';
    if (mobile.isEmpty) return null;
    return _mobile.hasMatch(mobile) ? null : 'Enter a valid mobile number';
  }

  static final RegExp _amount = RegExp(r'^\d{1,13}(\.\d{1,2})?$');

  /// A positive money amount with at most two decimals.
  static String? positiveAmount(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter an amount';
    final Decimal? parsed = _amount.hasMatch(text)
        ? Decimal.tryParse(text)
        : null;
    if (parsed == null) return 'Enter a valid amount, e.g. 250.50';
    return parsed > Decimal.zero ? null : 'Amount must be more than zero';
  }

  /// A money amount with at most two decimals; zero is allowed.
  static String? nonNegativeAmount(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter an amount (0 if none)';
    return _amount.hasMatch(text) ? null : 'Enter a valid amount, e.g. 250.50';
  }

  static String? name(String? value, String fieldName) =>
      (value == null || value.trim().isEmpty) ? 'Enter $fieldName' : null;
}
