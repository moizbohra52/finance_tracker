import 'dart:io';

import 'package:finance_tracker/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Supabase upi_id CHECK can run in Postgres and matches the app', () {
    // The newest migration that defines the constraint is the one in force.
    final List<File> defining =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where(
              (File f) => f.readAsStringSync().contains(
                'constraint user_settings_upi_id_check',
              ),
            )
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
    final String pattern = RegExp(
      r"upi_id ~ '([^']+)'",
    ).allMatches(defining.last.readAsStringSync()).last.group(1)!;

    // Postgres allows a repetition count of at most 255. It only compiles the
    // pattern when a UPI ID is first written, so a larger count lets the
    // migration apply and then fails every settings sync (SQLSTATE 2201B).
    for (final Match bound in RegExp(
      r'\{(\d+)(?:,(\d*))?\}',
    ).allMatches(pattern)) {
      for (final String? count in <String?>[bound.group(1), bound.group(2)]) {
        if (count == null || count.isEmpty) continue;
        expect(int.parse(count), lessThanOrEqualTo(255), reason: pattern);
      }
    }
    expect(pattern, Validators.upiIdPattern);
  });

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
