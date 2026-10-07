/// Compile-time environment values, supplied with
/// `flutter run --dart-define-from-file=env.json`.
///
/// Only public client values belong here. The Supabase service-role key or
/// any other server secret must never be added: anything compiled into the
/// app can be extracted from the binary.
abstract final class AppEnv {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Publishable (client) key; a legacy anon key also works.
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
