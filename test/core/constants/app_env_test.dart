import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnv Environment Configuration', () {
    test('defaults to dev in test and debug mode', () {
      expect(AppEnv.current, Environment.dev);
      expect(AppEnv.isDev, isTrue);
      expect(AppEnv.isProd, isFalse);
    });

    test('dev database is finance_tracker_dev.db', () {
      expect(AppEnv.databaseName, 'finance_tracker_dev.db');
      expect(AppDatabase.databaseName, 'finance_tracker_dev.db');
    });

    test(
      'has no hardcoded credentials when env.json is not passed',
      () {
        expect(AppEnv.isConfigured, isFalse);
        expect(AppEnv.supabaseUrl, isEmpty);
        expect(AppEnv.supabasePublishableKey, isEmpty);
      },
      skip:
          const bool.hasEnvironment('DEV_SUPABASE_URL') ||
          const bool.hasEnvironment('SUPABASE_URL'),
    );
  });
}
