import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/features/auth/controllers/change_password_controller.dart';
import 'package:finance_tracker/features/auth/widgets/auth_form_layout.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ChangePasswordView extends GetView<ChangePasswordController> {
  const ChangePasswordView({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthFormLayout(
      title: 'Change password',
      subtitle: 'Confirm your current password, then choose a new one.',
      children: <Widget>[
        Form(
          key: controller.formKey,
          child: AutofillGroup(
            child: Column(
              children: <Widget>[
                AppTextField(
                  label: 'Current password',
                  controller: controller.currentPasswordController,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.password],
                  validator: (String? value) =>
                      Validators.requiredField(value, 'current password'),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'New password',
                  helperText: 'At least 8 characters, with letters and numbers',
                  controller: controller.newPasswordController,
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
                    () => controller.newPasswordController.text,
                  ),
                  onFieldSubmitted: (_) => controller.changePassword(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SubmitErrorMessage(controller.submission),
        Obx(
          () => AppButton(
            label: 'Change password',
            isLoading: controller.submission.isBusy.value,
            onPressed: controller.changePassword,
          ),
        ),
      ],
    );
  }
}
