import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/features/auth/controllers/reset_password_controller.dart';
import 'package:finance_tracker/features/auth/widgets/auth_form_layout.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ResetPasswordView extends GetView<ResetPasswordController> {
  const ResetPasswordView({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthFormLayout(
      title: 'Choose a new password',
      subtitle: 'You will use it the next time you sign in.',
      children: <Widget>[
        Form(
          key: controller.formKey,
          child: AutofillGroup(
            child: Column(
              children: <Widget>[
                AppTextField(
                  label: 'New password',
                  helperText: 'At least 8 characters, with letters and numbers',
                  controller: controller.passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.newPassword],
                  validator: Validators.newPassword,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Confirm new password',
                  controller: controller.confirmPasswordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  validator: Validators.confirmPassword(
                    () => controller.passwordController.text,
                  ),
                  onFieldSubmitted: (_) => controller.savePassword(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SubmitErrorMessage(controller.submission),
        Obx(
          () => AppButton(
            label: 'Save password',
            isLoading: controller.submission.isBusy.value,
            onPressed: controller.savePassword,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(
          () => TextButton(
            onPressed: controller.submission.isBusy.value
                ? null
                : controller.cancel,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}
