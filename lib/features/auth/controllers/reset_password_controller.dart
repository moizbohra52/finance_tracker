import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Opened from the password-reset email link, which signs the user in with a
/// short-lived recovery session.
class ResetPasswordController extends GetxController {
  ResetPasswordController(this._authRepository);

  final AuthRepository _authRepository;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final SubmitState submission = SubmitState();

  Future<void> savePassword() async {
    if (!formKey.currentState!.validate()) return;
    final bool succeeded = await submission.run(
      () => _authRepository.updatePassword(passwordController.text),
    );
    if (succeeded) {
      AppSnackbar.show('Your password has been updated.');
      await Get.offAllNamed<void>(AppRoutes.dashboard);
    }
  }

  /// Leaves without changing the password; ends the recovery session.
  Future<void> cancel() => _authRepository.signOut();

  @override
  void onClose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
