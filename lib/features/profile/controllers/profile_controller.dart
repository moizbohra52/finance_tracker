import 'dart:async';
import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/domain/services/avatar_rules.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:get/get.dart';

/// Profile details, profile photo, sign-out and account deletion.
///
/// Currency and date formats are account preferences, edited in Settings, so
/// they are not here.
class ProfileController extends GetxController {
  ProfileController(this._profiles, this._authRepository);

  final ProfileRepository _profiles;
  final AuthRepository _authRepository;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();

  /// Saved full name, for greetings elsewhere in the app.
  final RxString displayName = ''.obs;

  /// Storage path of the photo, or null when there is none.
  final RxnString avatarPath = RxnString();

  /// Link the photo is shown from. Null means show the fallback picture.
  final RxnString avatarLink = RxnString();
  final RxBool avatarBusy = false.obs;
  final RxnString avatarError = RxnString();

  /// The device's time zone, saved with the profile and shown read-only.
  final RxString timezone = ''.obs;

  final RxBool isLoading = true.obs;
  final RxnString loadError = RxnString();
  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();

  String get email => _authRepository.currentEmail ?? '';

  @override
  void onInit() {
    super.onInit();
    loadProfile();
  }

  Future<void> loadProfile() async {
    isLoading.value = true;
    loadError.value = null;
    try {
      final Profile profile = await _profiles.fetchProfile();
      _fill(profile);
      avatarLink.value = await _linkFor(profile.avatarPath);
    } on AppException catch (failure) {
      loadError.value = failure.message;
    } finally {
      isLoading.value = false;
    }
    // Not awaited: the device's time zone must never hold up the screen.
    unawaited(_loadTimezone());
  }

  Future<bool> saveProfile() async {
    // The same rules the form shows inline, so a save never sends bad data
    // even when the form is not on screen.
    formKey.currentState?.validate();
    if (Validators.profileName(fullNameController.text) != null ||
        Validators.optionalMobile(mobileController.text) != null) {
      return false;
    }
    final String mobile = mobileController.text.trim();
    final bool saved = await save.run(() async {
      _fill(
        await _profiles.updateProfile(
          fullName: fullNameController.text.trim(),
          mobile: mobile.isEmpty ? null : mobile,
          clearMobile: mobile.isEmpty,
          timezone: timezone.value.isEmpty ? null : timezone.value,
        ),
      );
    });
    if (saved) AppSnackbar.show('Profile saved.');
    return saved;
  }

  /// Uploads a photo the user picked. The shown photo changes only after the
  /// upload and the profile update both succeed, so a failure keeps the
  /// previous photo. [fileName] is used for the type and size checks.
  Future<bool> uploadAvatar(String fileName, Uint8List bytes) async {
    final AvatarProblem? problem = AvatarRules.check(
      fileName: fileName,
      byteLength: bytes.length,
    );
    if (problem != null) {
      avatarError.value = problem.message;
      return false;
    }
    avatarBusy.value = true;
    avatarError.value = null;
    String? uploaded;
    try {
      final String extension = AvatarRules.extensionOf(fileName);
      uploaded = await _profiles.uploadAvatar(
        bytes: bytes,
        extension: extension,
        contentType: AvatarRules.contentTypes[extension]!,
      );
      final String? previous = avatarPath.value;
      _fill(await _profiles.updateProfile(avatarPath: uploaded));
      avatarLink.value = await _linkFor(uploaded);
      if (previous != null && previous != uploaded) {
        await _removeQuietly(previous);
      }
      AppSnackbar.show('Profile photo updated.');
      return true;
    } on AppException catch (failure) {
      avatarError.value = failure.message;
      // The new file is not referenced by the profile, so it must not stay.
      if (uploaded != null) await _removeQuietly(uploaded);
      return false;
    } finally {
      avatarBusy.value = false;
    }
  }

  /// AuthController returns the app to sign-in on the signed-out event.
  Future<void> signOut() => _authRepository.signOut();

  /// The account is only deleted after the password is confirmed, so the photo
  /// is removed inside that step, not before it. On success AuthController
  /// returns the app to sign-in; on failure the reason is in [deletion].
  Future<bool> deleteAccount(String password) async {
    final bool deleted = await deletion.run(
      () => _authRepository.deleteAccount(
        password: password,
        beforeDelete: _removeAvatarBeforeDelete,
      ),
    );
    if (deleted) AppSnackbar.show('Your account has been deleted.');
    return deleted;
  }

  Future<void> _removeAvatarBeforeDelete() async {
    final String? path = avatarPath.value;
    if (path != null) await _removeQuietly(path);
  }

  /// Best effort: a photo that cannot be removed must not block the caller.
  Future<void> _removeQuietly(String path) async {
    try {
      await _profiles.removeAvatar(path);
    } on AppException {
      // The profile no longer points at it. It is left behind, not shown.
    }
  }

  /// Photos saved before the private bucket were full public URLs, so they
  /// are used as they are. Anything else is a storage path and gets a link.
  /// A link that cannot be made shows the fallback picture rather than failing
  /// the whole profile.
  Future<String?> _linkFor(String? pathOrUrl) async {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    try {
      return await _profiles.avatarLink(pathOrUrl);
    } on AppException {
      return null;
    }
  }

  Future<void> _loadTimezone() async {
    try {
      timezone.value = (await FlutterTimezone.getLocalTimezone()).identifier;
    } on Object {
      // No time zone on this platform (tests, desktop): the field stays empty.
    }
  }

  void _fill(Profile profile) {
    fullNameController.text = profile.fullName ?? '';
    mobileController.text = profile.mobile ?? '';
    displayName.value = profile.fullName ?? '';
    avatarPath.value = profile.avatarPath;
  }

  @override
  void onClose() {
    fullNameController.dispose();
    mobileController.dispose();
    super.onClose();
  }
}
