import 'package:finance_tracker/domain/services/avatar_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const int oneKb = 1024;

  group('avatar file rules', () {
    test('accepts JPEG, PNG and WebP, in any letter case', () {
      for (final String name in <String>[
        'photo.jpg',
        'photo.JPEG',
        'selfie.png',
        'avatar.WebP',
      ]) {
        expect(
          AvatarRules.check(fileName: name, byteLength: oneKb),
          isNull,
          reason: name,
        );
      }
    });

    test('rejects other formats, including files with no extension', () {
      for (final String name in <String>[
        'animation.gif',
        'scan.heic',
        'document.pdf',
        'photo',
      ]) {
        expect(
          AvatarRules.check(fileName: name, byteLength: oneKb),
          AvatarProblem.unsupportedType,
          reason: name,
        );
      }
    });

    test('rejects an empty file', () {
      expect(
        AvatarRules.check(fileName: 'photo.jpg', byteLength: 0),
        AvatarProblem.empty,
      );
    });

    test('allows exactly 2 MiB and rejects one byte more', () {
      expect(
        AvatarRules.check(
          fileName: 'photo.jpg',
          byteLength: AvatarRules.maxBytes,
        ),
        isNull,
      );
      expect(
        AvatarRules.check(
          fileName: 'photo.jpg',
          byteLength: AvatarRules.maxBytes + 1,
        ),
        AvatarProblem.tooLarge,
      );
    });

    test('a type problem is reported before a size problem', () {
      expect(
        AvatarRules.check(
          fileName: 'huge.gif',
          byteLength: AvatarRules.maxBytes * 2,
        ),
        AvatarProblem.unsupportedType,
      );
    });

    test('every problem has a message the user can act on', () {
      for (final AvatarProblem problem in AvatarProblem.values) {
        expect(problem.message, isNotEmpty);
      }
      expect(AvatarProblem.tooLarge.message, contains('2 MB'));
    });

    test('each accepted extension maps to the MIME type sent to storage', () {
      expect(AvatarRules.contentTypes['jpg'], 'image/jpeg');
      expect(AvatarRules.contentTypes['jpeg'], 'image/jpeg');
      expect(AvatarRules.contentTypes['png'], 'image/png');
      expect(AvatarRules.contentTypes['webp'], 'image/webp');
    });
  });
}
