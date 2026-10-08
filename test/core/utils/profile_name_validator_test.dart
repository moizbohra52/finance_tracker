import 'package:finance_tracker/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profile name', () {
    test('accepts ordinary names, with dots, apostrophes and hyphens', () {
      for (final String name in <String>[
        'Asha Rao',
        "Anita-Marie O'Neil",
        'A. K. Menon',
        'Zoë Müller',
      ]) {
        expect(Validators.profileName(name), isNull, reason: name);
      }
    });

    test('accepts names in other scripts', () {
      expect(Validators.profileName('आशा राव'), isNull);
    });

    test('is required, and whitespace is not a name', () {
      expect(Validators.profileName(null), 'Enter your name');
      expect(Validators.profileName(''), 'Enter your name');
      expect(Validators.profileName('   '), 'Enter your name');
    });

    test('rejects digits and symbols', () {
      for (final String name in <String>['Asha 2', 'Asha@Rao', 'Asha_Rao']) {
        expect(
          Validators.profileName(name),
          'Use letters, spaces, dots, apostrophes or hyphens only',
          reason: name,
        );
      }
    });

    test('a name must start with a letter', () {
      expect(
        Validators.profileName("'Asha"),
        'Use letters, spaces, dots, apostrophes or hyphens only',
      );
    });

    test('is limited to 80 characters after trimming', () {
      expect(Validators.profileName('A' * 80), isNull);
      expect(
        Validators.profileName('A' * 81),
        'Keep your name under 80 characters',
      );
      expect(Validators.profileName('  ${'A' * 80}  '), isNull);
    });
  });
}
