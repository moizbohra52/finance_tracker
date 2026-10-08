abstract final class AppConstants {
  static const String appName = 'Track Day';
  static const String defaultLocale = 'en_IN';

  /// Shown on the About screen. Must match the version in pubspec.yaml.
  static const String appVersion = '1.0.0';

  /// Where Supabase auth emails (confirmation, password reset) send the user
  /// back. Must match the scheme in AndroidManifest.xml and Info.plist, and be
  /// in the Supabase project's redirect allow list.
  static const String authRedirectUrl =
      'com.finance_tracker.app://auth-callback';
}
