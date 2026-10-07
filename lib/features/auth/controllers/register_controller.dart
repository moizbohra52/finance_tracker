import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class RegisterController extends GetxController {
  RegisterController(this._authRepository);

  final AuthRepository _authRepository;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final SubmitState submission = SubmitState();

  /// Set when the project requires email confirmation: the address the
  /// confirmation link was sent to.
  final RxnString confirmationSentTo = RxnString();

  /// When no confirmation is needed, AuthController navigates on sign-in.
  Future<void> register() async {
    if (!formKey.currentState!.validate()) return;
    final String email = emailController.text.trim();
    bool signedIn = false;
    final bool succeeded = await submission.run(() async {
      signedIn = await _authRepository.signUp(
        fullName: fullNameController.text.trim(),
        email: email,
        password: passwordController.text,
      );
    });
    if (succeeded && !signedIn) confirmationSentTo.value = email;
  }

  @override
  void onClose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
