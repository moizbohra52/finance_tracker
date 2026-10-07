import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class LoginController extends GetxController {
  LoginController(this._authRepository);

  final AuthRepository _authRepository;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final SubmitState submission = SubmitState();

  /// AuthController navigates to the dashboard on success.
  Future<void> signIn() async {
    if (!formKey.currentState!.validate()) return;
    await submission.run(
      () => _authRepository.signIn(
        email: emailController.text.trim(),
        password: passwordController.text,
      ),
    );
  }

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
