import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/features/auth/controllers/add_account_controller.dart';
import 'package:finance_tracker/features/auth/widgets/auth_form_layout.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Sign-in form for one more account. The active account stays signed in,
/// and the app switches to the new one when the sign-in succeeds.
class AddAccountView extends GetView<AddAccountController> {
  const AddAccountView({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthFormLayout(
      title: 'Another account',
      subtitle:
          'Sign in to another account. You stay signed in to this one and '
          'can switch back at any time.',
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
                  onFieldSubmitted: (_) => controller.submit(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SubmitErrorMessage(controller.submission),
        Obx(
          () => AppButton(
            label: 'Sign in and switch',
            isLoading: controller.submission.isBusy.value,
            onPressed: controller.submit,
          ),
        ),
      ],
    );
  }
}
