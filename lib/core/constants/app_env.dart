import 'package:flutter/foundation.dart';

/// Available application environments.
enum Environment {
  dev,
  prod;

  bool get isDev => this == Environment.dev;
  bool get isProd => this == Environment.prod;
}

/// Environment configuration.
///
/// Features:
/// 1. Automatic detection: `flutter run` (debug) automatically selects [Environment.dev].
///    `flutter run --release` or `flutter build` automatically selects [Environment.prod].
/// 2. Explicit overrides: Pass `--dart-define=ENV=dev` or `--dart-define=ENV=prod`.
/// 3. Credentials come only from `--dart-define-from-file=env.json`, which holds
///    `DEV_*` and `PROD_*` keys; the active environment picks its pair.
/// 4. Database segregation: Dev runs on `finance_tracker_dev.db` while Prod runs
///    on `finance_tracker.db` to prevent mixing dev test data with production.
abstract final class AppEnv {
  // Explicit compile-time defines.
  static const String _explicitEnv = String.fromEnvironment('ENV');
  static const String _rawSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _rawSupabaseKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static const String _devSupabaseUrl = String.fromEnvironment(
    'DEV_SUPABASE_URL',
  );
  static const String _devSupabaseKey = String.fromEnvironment(
    'DEV_SUPABASE_PUBLISHABLE_KEY',
  );

  static const String _prodSupabaseUrl = String.fromEnvironment(
    'PROD_SUPABASE_URL',
  );
  static const String _prodSupabaseKey = String.fromEnvironment(
    'PROD_SUPABASE_PUBLISHABLE_KEY',
  );

  /// Current active environment.
  static Environment get current {
    final String env = _explicitEnv.toLowerCase().trim();
    if (env == 'prod' || env == 'production') {
      return Environment.prod;
    }
    if (env == 'dev' || env == 'development') {
      return Environment.dev;
    }
    // Auto-detect based on build mode:
    return kReleaseMode ? Environment.prod : Environment.dev;
  }

  static bool get isDev => current == Environment.dev;
  static bool get isProd => current == Environment.prod;

  /// Active Supabase URL.
  static String get supabaseUrl {
    final String scoped = isDev ? _devSupabaseUrl : _prodSupabaseUrl;
    return scoped.isNotEmpty ? scoped : _rawSupabaseUrl;
  }

  /// Active Supabase publishable key.
  static String get supabasePublishableKey {
    final String scoped = isDev ? _devSupabaseKey : _prodSupabaseKey;
    return scoped.isNotEmpty ? scoped : _rawSupabaseKey;
  }

  /// Name of the SQLite database file for the current environment.
  /// Dev uses `finance_tracker_dev.db` and Prod uses `finance_tracker.db`.
  static String get databaseName =>
      isDev ? 'finance_tracker_dev.db' : 'finance_tracker.db';

  /// Whether Supabase credentials are configured for the active environment.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
