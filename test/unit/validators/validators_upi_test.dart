import 'package:finance_tracker/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a UPI ID is optional', () {
    expect(Validators.optionalUpiId(null), isNull);
    expect(Validators.optionalUpiId('  '), isNull);
  });

  test('accepts handle@bank IDs', () {
    expect(Validators.optionalUpiId('asha@okaxis'), isNull);
    expect(Validators.optionalUpiId(' asha.rao-1_x@ybl '), isNull);
    expect(Validators.optionalUpiId('9876543210@paytm'), isNull);
  });

  test('rejects anything else', () {
    for (final String bad in <String>[
      'asha',
      'asha@',
      '@ybl',
      'a b@ybl',
      'asha@ok-axis',
      'asha@ybl@x',
    ]) {
      expect(Validators.optionalUpiId(bad), isNotNull, reason: bad);
    }
  });
}
