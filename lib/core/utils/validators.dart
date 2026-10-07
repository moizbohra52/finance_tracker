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
}
