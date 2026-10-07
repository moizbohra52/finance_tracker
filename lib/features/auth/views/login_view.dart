import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/features/auth/controllers/login_controller.dart';
import 'package:finance_tracker/features/auth/widgets/auth_form_layout.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginView extends GetView<LoginController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthFormLayout(
      title: 'Welcome back',
      subtitle: 'Sign in to see your balances.',
      children: <Widget>[
        Form(
          key: controller.formKey,
          child: AutofillGroup(
            child: Column(
              children: <Widget>[
                AppTextField(
                  label: 'Email',
                  controller: controller.emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.email],
                  validator: Validators.email,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Password',
                  controller: controller.passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.password],
                  validator: (String? value) =>
                      Validators.requiredField(value, 'password'),
                  onFieldSubmitted: (_) => controller.signIn(),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Get.toNamed<void>(AppRoutes.forgotPassword),
            child: const Text('Forgot password?'),
          ),
        ),
        SubmitErrorMessage(controller.submission),
        Obx(
          () => AppButton(
            label: 'Sign in',
            isLoading: controller.submission.isBusy.value,
            onPressed: controller.signIn,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            const Text("Don't have an account?"),
            TextButton(
              onPressed: () => Get.offNamed<void>(AppRoutes.register),
              child: const Text('Create one'),
            ),
          ],
        ),
      ],
    );
  }
}
