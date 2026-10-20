import 'package:finance_tracker/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.optionalMobile', () {
    test('returns null for null or empty input', () {
      expect(Validators.optionalMobile(null), isNull);
      expect(Validators.optionalMobile(''), isNull);
      expect(Validators.optionalMobile('   '), isNull);
    });

    test('validates single valid mobile number', () {
      expect(Validators.optionalMobile('+919876543210'), isNull);
      expect(Validators.optionalMobile('9876543210'), isNull);
      expect(Validators.optionalMobile('+1 555-123-4567'), isNull);
    });

    test('validates multiple valid mobile numbers separated by comma or semicolon', () {
      expect(
        Validators.optionalMobile('+919876543210, 9123456789'),
        isNull,
      );
      expect(
        Validators.optionalMobile('9876543210; +91 9123456789; 9988776655'),
        isNull,
      );
    });

    test('rejects invalid single number', () {
      expect(
        Validators.optionalMobile('123'),
        'Enter a valid mobile number',
      );
      expect(
        Validators.optionalMobile('abcd'),
        'Enter a valid mobile number',
      );
    });

    test('rejects if any number in multiple list is invalid', () {
      expect(
        Validators.optionalMobile('9876543210, invalid_num'),
        'Enter a valid mobile number',
      );
      expect(
        Validators.optionalMobile('123; 9876543210'),
        'Enter a valid mobile number',
      );
    });
  });
}
