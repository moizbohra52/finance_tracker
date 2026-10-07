import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class ForgotPasswordController extends GetxController {
  ForgotPasswordController(this._authRepository);

  final AuthRepository _authRepository;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final SubmitState submission = SubmitState();
  final RxnString linkSentTo = RxnString();

  Future<void> sendResetLink() async {
    if (!formKey.currentState!.validate()) return;
    final String email = emailController.text.trim();
    final bool succeeded = await submission.run(
      () => _authRepository.sendPasswordReset(email),
    );
    if (succeeded) linkSentTo.value = email;
  }

  @override
  void onClose() {
    emailController.dispose();
    super.onClose();
  }
}
