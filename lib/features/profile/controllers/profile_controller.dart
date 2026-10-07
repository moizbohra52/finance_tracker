import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Profile basics (name, mobile) plus sign-out and account deletion.
/// Avatar, currency and timezone arrive with the full profile in Phase 10.
class ProfileController extends GetxController {
  ProfileController(this._profileRepository, this._authRepository);

  final ProfileRepository _profileRepository;
  final AuthRepository _authRepository;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();

  /// Saved full name, for greetings elsewhere in the app.
  final RxString displayName = ''.obs;

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
      _fill(await _profileRepository.fetchProfile());
    } on AppException catch (failure) {
      loadError.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> saveProfile() async {
    if (!formKey.currentState!.validate()) return;
    final String mobile = mobileController.text.trim();
    final bool succeeded = await save.run(() async {
      _fill(
        await _profileRepository.updateProfile(
          fullName: fullNameController.text.trim(),
          mobile: mobile.isEmpty ? null : mobile,
        ),
      );
    });
    if (succeeded) AppSnackbar.show('Profile saved.');
  }

  /// AuthController returns the app to sign-in on the signed-out event.
  Future<void> signOut() => _authRepository.signOut();

  /// On success AuthController returns the app to sign-in; on failure the
  /// reason is in [deletion].
  Future<void> deleteAccount(String password) async {
    final bool succeeded = await deletion.run(
      () => _authRepository.deleteAccount(password: password),
    );
    if (succeeded) AppSnackbar.show('Your account has been deleted.');
  }

  void _fill(Profile profile) {
    fullNameController.text = profile.fullName ?? '';
    mobileController.text = profile.mobile ?? '';
    displayName.value = profile.fullName ?? '';
  }

  @override
  void onClose() {
    fullNameController.dispose();
    mobileController.dispose();
    super.onClose();
  }
}
