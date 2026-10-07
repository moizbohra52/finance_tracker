abstract final class AppConstants {
  static const String appName = 'Finance Tracker';

  /// Where Supabase auth emails (confirmation, password reset) send the user
  /// back. Must match the scheme in AndroidManifest.xml and Info.plist, and be
  /// in the Supabase project's redirect allow list.
  static const String authRedirectUrl =
      'com.example.financetracker://auth-callback';
}
