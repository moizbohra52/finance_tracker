import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/features/auth/controllers/account_switch_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Signs in to one more account while the active one stays signed in.
class AddAccountController extends GetxController {
  AddAccountController(this._accounts);

  final AccountSwitchController _accounts;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final SubmitState submission = SubmitState();

  /// AccountSwitchController switches to the new account on success.
  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    await submission.run(
      () => _accounts.addAccount(
        email: emailController.text.trim(),
        password: passwordController.text,
      ),
    );
  }

}
