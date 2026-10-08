import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// The signed-in user's profile, with a photo at [avatarPath].
Profile profileWithPhoto(String? avatarPath) => Profile(
  id: 'user-1',
  fullName: 'Asha Rao',
  mobile: '+91 98765 43210',
  avatarPath: avatarPath,
  currencyCode: 'INR',
  timezone: 'Asia/Kolkata',
);

void main() {
  // The controller shows snack bars, which needs the widget binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late ProfileController controller;
  final Uint8List photo = Uint8List.fromList(List<int>.filled(1024, 7));

  setUp(() async {
    auth = FakeAuthRepository(signedIn: true);
    profiles = FakeProfileRepository();
    controller = ProfileController(profiles, auth);
    await controller.loadProfile();
  });

  group('profile details', () {
    test('loads the saved name and mobile', () {
      expect(controller.fullNameController.text, 'Asha Rao');
      expect(controller.mobileController.text, '+91 98765 43210');
      expect(controller.displayName.value, 'Asha Rao');
    });

    test('an invalid name is rejected before anything is sent', () async {
      controller.fullNameController.text = 'Asha 2';

      expect(await controller.saveProfile(), isFalse);
      expect(profiles.profile.fullName, 'Asha Rao');
    });

    test(
      'an invalid mobile number is rejected before anything is sent',
      () async {
        controller.mobileController.text = '12';

        expect(await controller.saveProfile(), isFalse);
        expect(profiles.profile.mobile, '+91 98765 43210');
      },
    );

    test('a cleared mobile number is removed, not left as it was', () async {
      controller.mobileController.text = '   ';

      expect(await controller.saveProfile(), isTrue);
      expect(profiles.profile.mobile, isNull);
    });

    test('the name and mobile are saved trimmed', () async {
      controller.fullNameController.text = '  Asha Rao  ';
      controller.mobileController.text = ' +91 98765 43210 ';

      expect(await controller.saveProfile(), isTrue);
      expect(profiles.profile.fullName, 'Asha Rao');
      expect(profiles.profile.mobile, '+91 98765 43210');
    });

    test('a failed save keeps the form and shows the error', () async {
      profiles.nextError = const NetworkFailure();

      expect(await controller.saveProfile(), isFalse);
      expect(controller.save.error.value, const NetworkFailure().message);
      expect(controller.fullNameController.text, 'Asha Rao');
    });

    test(
      'a failed photo link shows the fallback, not a failed profile',
      () async {
        profiles.profile = profileWithPhoto('user-1/old.jpg');
        profiles.failLinks = true;
        controller = ProfileController(profiles, auth);
        await controller.loadProfile();

        expect(controller.loadError.value, isNull);
        expect(controller.fullNameController.text, 'Asha Rao');
        expect(controller.avatarLink.value, isNull);
      },
    );
  });

  group('profile photo', () {
    test('a valid photo is uploaded, saved to the profile and shown', () async {
      expect(await controller.uploadAvatar('me.jpg', photo), isTrue);

      expect(profiles.uploads, <String>['user-1/0.jpg']);
      expect(profiles.profile.avatarPath, 'user-1/0.jpg');
      expect(controller.avatarPath.value, 'user-1/0.jpg');
      expect(controller.avatarLink.value, contains('user-1/0.jpg'));
      expect(controller.avatarBusy.value, isFalse, reason: 'progress ends');
      expect(controller.avatarError.value, isNull);
    });

    test(
      'replacing a photo removes the old file once the new one is saved',
      () async {
        await controller.uploadAvatar('first.jpg', photo);
        await controller.uploadAvatar('second.png', photo);

        expect(profiles.removed, <String>['user-1/0.jpg']);
        expect(profiles.profile.avatarPath, 'user-1/1.png');
      },
    );

    test('an unsupported type is refused without uploading', () async {
      expect(await controller.uploadAvatar('scan.gif', photo), isFalse);

      expect(profiles.uploads, isEmpty);
      expect(controller.avatarError.value, contains('JPG, PNG or WebP'));
    });

    test('a photo over 2 MB is refused without uploading', () async {
      final Uint8List tooBig = Uint8List(2 * 1024 * 1024 + 1);

      expect(await controller.uploadAvatar('big.jpg', tooBig), isFalse);

      expect(profiles.uploads, isEmpty);
      expect(controller.avatarError.value, contains('2 MB'));
    });

    test('a failed upload keeps the current photo', () async {
      await controller.uploadAvatar('first.jpg', photo);
      profiles.failUploads = true;

      expect(await controller.uploadAvatar('second.jpg', photo), isFalse);

      expect(controller.avatarPath.value, 'user-1/0.jpg');
      expect(profiles.removed, isEmpty);
      expect(controller.avatarError.value, isNotNull);
      expect(controller.avatarBusy.value, isFalse);
    });

    test(
      'an upload that cannot be attached to the profile is cleaned up',
      () async {
        await controller.uploadAvatar('first.jpg', photo);
        profiles.failUpdates = true;

        expect(await controller.uploadAvatar('second.jpg', photo), isFalse);

        // The new file is not referenced by the profile, so it is removed; the
        // old photo stays exactly as it was.
        expect(profiles.removed, <String>['user-1/1.jpg']);
        expect(controller.avatarPath.value, 'user-1/0.jpg');
        expect(controller.avatarError.value, isNotNull);
      },
    );

    test('a photo saved as a public link before is still shown', () async {
      profiles.profile = profileWithPhoto('https://cdn.example/old.jpg');
      controller = ProfileController(profiles, auth);
      await controller.loadProfile();

      expect(controller.avatarLink.value, 'https://cdn.example/old.jpg');
    });
  });

  group('account deletion', () {
    test('a wrong password removes nothing and keeps the photo', () async {
      await controller.uploadAvatar('me.jpg', photo);
      auth.nextError = const AuthFailure('Your password is incorrect.');

      expect(await controller.deleteAccount('wrong-pass'), isFalse);

      expect(profiles.removed, isEmpty);
      expect(controller.avatarPath.value, 'user-1/0.jpg');
      expect(controller.deletion.error.value, 'Your password is incorrect.');
      expect(auth.isSignedIn, isTrue, reason: 'nothing was deleted');
    });

    test(
      'a confirmed password removes the photo, then deletes the account',
      () async {
        await controller.uploadAvatar('me.jpg', photo);

        expect(await controller.deleteAccount('right-pass1'), isTrue);

        expect(profiles.removed, <String>['user-1/0.jpg']);
        expect(auth.calls, <String>['deleteAccount']);
        expect(auth.isSignedIn, isFalse);
      },
    );

    test('a failed photo removal does not stop the deletion', () async {
      await controller.uploadAvatar('me.jpg', photo);
      profiles.nextError = const NetworkFailure();

      expect(await controller.deleteAccount('right-pass1'), isTrue);
      expect(auth.isSignedIn, isFalse);
    });
  });
}
