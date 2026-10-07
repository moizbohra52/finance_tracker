import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/features/auth/controllers/forgot_password_controller.dart';
import 'package:finance_tracker/features/auth/widgets/auth_form_layout.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ForgotPasswordView extends GetView<ForgotPasswordController> {
  const ForgotPasswordView({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthFormLayout(
      title: 'Reset your password',
      subtitle: "Enter your account email and we'll send you a reset link.",
      children: <Widget>[
        Form(
          key: controller.formKey,
          child: AppTextField(
            label: 'Email',
            controller: controller.emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.email],
            validator: Validators.email,
            onFieldSubmitted: (_) => controller.sendResetLink(),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Obx(() {
          final String? sentTo = controller.linkSentTo.value;
          return sentTo == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: InlineMessage(
                    tone: InlineMessageTone.success,
                    message:
                        'If an account exists for $sentTo, a reset link is on '
                        'its way. Open it on this device.',
                  ),
                );
        }),
        SubmitErrorMessage(controller.submission),
        Obx(
          () => AppButton(
            label: controller.linkSentTo.value == null
                ? 'Send reset link'
                : 'Send again',
            isLoading: controller.submission.isBusy.value,
            onPressed: controller.sendResetLink,
          ),
        ),
      ],
    );
  }
}
