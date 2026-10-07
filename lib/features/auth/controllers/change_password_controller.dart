import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class ChangePasswordController extends GetxController {
  ChangePasswordController(this._authRepository);

  final AuthRepository _authRepository;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController currentPasswordController =
      TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final SubmitState submission = SubmitState();

  Future<void> changePassword() async {
    if (!formKey.currentState!.validate()) return;
    final bool succeeded = await submission.run(
      () => _authRepository.changePassword(
        currentPassword: currentPasswordController.text,
        newPassword: newPasswordController.text,
      ),
    );
    if (succeeded) {
      AppSnackbar.show('Your password has been changed.');
      Get.back<void>();
    }
  }

  @override
  void onClose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
