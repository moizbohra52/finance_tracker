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
/// 2. Explicit overrides: Pass `--dart-define=ENV=dev` or `--dart-define=ENV=prod`,
///    or `--dart-define-from-file=env.dev.json`.
/// 3. Default dev fallback: Automatically uses local dev credentials when running
///    without any flags, eliminating the need to pass `--dart-define-from-file`.
/// 4. Database segregation: Dev runs on `finance_tracker_dev.db` while Prod runs
///    on `finance_tracker.db` to prevent mixing dev test data with production.
abstract final class AppEnv {
  // Built-in dev defaults (active during debug mode when no CLI defines are given).
  static const String _defaultDevSupabaseUrl =
      'https://xnnkbytlpyqtqwhxscsr.supabase.co';
  static const String _defaultDevSupabaseKey =
      'sb_publishable_ZQquvUYXJE6VexbTn_fB2g_LxTa_K-2';

  // Built-in prod defaults (active during release mode when no CLI defines are given).
  static const String _defaultProdSupabaseUrl =
      'https://ccqhtbnpzbtzzstaedgc.supabase.co';
  static const String _defaultProdSupabaseKey =
      'sb_publishable_mYltOWzW2-TRR5C9thZ-0w_mX8nzgfL';

  // Explicit compile-time defines.
  static const String _explicitEnv = String.fromEnvironment('ENV');
  static const String _rawSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _rawSupabaseKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static const String _devSupabaseUrl =
      String.fromEnvironment('DEV_SUPABASE_URL');
  static const String _devSupabaseKey =
      String.fromEnvironment('DEV_SUPABASE_PUBLISHABLE_KEY');

  static const String _prodSupabaseUrl =
      String.fromEnvironment('PROD_SUPABASE_URL');
  static const String _prodSupabaseKey =
      String.fromEnvironment('PROD_SUPABASE_PUBLISHABLE_KEY');

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
    if (isDev) {
      if (_devSupabaseUrl.isNotEmpty) return _devSupabaseUrl;
      if (_rawSupabaseUrl.isNotEmpty) return _rawSupabaseUrl;
      return _defaultDevSupabaseUrl;
    } else {
      if (_prodSupabaseUrl.isNotEmpty) return _prodSupabaseUrl;
      if (_rawSupabaseUrl.isNotEmpty) return _rawSupabaseUrl;
      return _defaultProdSupabaseUrl;
    }
  }

  /// Active Supabase publishable key.
  static String get supabasePublishableKey {
    if (isDev) {
      if (_devSupabaseKey.isNotEmpty) return _devSupabaseKey;
      if (_rawSupabaseKey.isNotEmpty) return _rawSupabaseKey;
      return _defaultDevSupabaseKey;
    } else {
      if (_prodSupabaseKey.isNotEmpty) return _prodSupabaseKey;
      if (_rawSupabaseKey.isNotEmpty) return _rawSupabaseKey;
      return _defaultProdSupabaseKey;
    }
  }

  /// Name of the SQLite database file for the current environment.
  /// Dev uses `finance_tracker_dev.db` and Prod uses `finance_tracker.db`.
  static String get databaseName =>
      isDev ? 'finance_tracker_dev.db' : 'finance_tracker.db';

  /// Whether Supabase credentials are configured for the active environment.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
