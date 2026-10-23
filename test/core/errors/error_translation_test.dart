import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/core/services/backup_service.dart';
import 'package:finance_tracker/core/translations/app_translations.dart';
import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/transactions/widgets/receipt_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = AppLanguage.hindi.locale;
  });

  tearDown(() => Get.locale = AppLanguage.english.locale);

  test('a failure shows its message in the app language', () {
    expect(
      const NetworkFailure().message,
      hindi["Can't reach the server. Check your connection and try again."],
    );
    expect(
      mapSupabaseError(
        const AuthException('bad login', code: 'invalid_credentials'),
      ).message,
      hindi['Incorrect email or password.'],
    );
  });

  test('logs keep the English text', () {
    expect(
      const NetworkFailure().toString(),
      "NetworkFailure: Can't reach the server. Check your connection and try "
      'again.',
    );
    expect(
      mapSupabaseError(
        const AuthException('expired', code: 'session_expired'),
      ).toString(),
      'AuthFailure: Your session has expired. Please sign in again.',
    );
  });

  test('a rejected receipt photo says why in the app language', () {
    expect(
      receiptPhotoProblem('scan.gif', 10),
      hindi['Choose a JPG, PNG or WebP image.'],
    );
    expect(receiptPhotoProblem('bill.jpg', 10), isNull);
  });

  test('a rejected backup file says why in the app language', () {
    expect(
      const BackupService().validateBackup('').errorMessage,
      hindi['The selected backup file is empty.'],
    );
  });
}
