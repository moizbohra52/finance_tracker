abstract final class AppConstants {
  static const String appName = 'Finance Tracker';
  static const String defaultCurrencyCode = 'INR';
  static const String defaultLocale = 'en_IN';
  static const int currencyDecimalDigits = 2;

  /// Where Supabase auth emails (confirmation, password reset) send the user
  /// back. Must match the scheme in AndroidManifest.xml and Info.plist, and be
  /// in the Supabase project's redirect allow list.
  static const String authRedirectUrl =
      'com.example.financetracker://auth-callback';
}
