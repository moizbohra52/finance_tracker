import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/features/auth/controllers/register_controller.dart';
import 'package:finance_tracker/features/auth/widgets/auth_form_layout.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class RegisterView extends GetView<RegisterController> {
  const RegisterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final String? sentTo = controller.confirmationSentTo.value;
      if (sentTo != null) {
        return Scaffold(
          appBar: const AppAppBar(title: ''),
          body: SafeArea(
            child: EmptyState(
              icon: Icons.mark_email_unread_outlined,
              title: 'Check your email',
              message:
                  'We sent a confirmation link to $sentTo. Open it on this '
                  'device to finish creating your account.',
              actionLabel: 'Back to sign in',
              onAction: () => Get.offNamed<void>(AppRoutes.login),
            ),
          ),
        );
      }
      return const _RegisterForm();
    });
  }
}

class _RegisterForm extends GetView<RegisterController> {
  const _RegisterForm();

  @override
  Widget build(BuildContext context) {
    return AuthFormLayout(
      title: 'Create your account',
      subtitle: 'Track balances, spending and khata in one place.',
      children: <Widget>[
        Form(
          key: controller.formKey,
          child: AutofillGroup(
            child: Column(
              children: <Widget>[
                AppTextField(
                  label: 'Full name',
                  controller: controller.fullNameController,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.name],
                  validator: (String? value) =>
                      Validators.requiredField(value, 'name'),
                ),
                const SizedBox(height: AppSpacing.md),
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
                  helperText: 'At least 8 characters, with letters and numbers',
                  controller: controller.passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.newPassword],
                  validator: Validators.newPassword,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Confirm password',
                  controller: controller.confirmPasswordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  validator: Validators.confirmPassword(
                    () => controller.passwordController.text,
                  ),
                  onFieldSubmitted: (_) => controller.register(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SubmitErrorMessage(controller.submission),
        Obx(
          () => AppButton(
            label: 'Create account',
            isLoading: controller.submission.isBusy.value,
            onPressed: controller.register,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            const Text('Already have an account?'),
            TextButton(
              onPressed: () => Get.offNamed<void>(AppRoutes.login),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ],
    );
  }
}
