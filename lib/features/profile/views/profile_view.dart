import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/profile/widgets/delete_account_dialog.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProfileView extends GetView<ProfileController> {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Profile'),
      body: const SafeArea(child: ProfileContent()),
    );
  }
}

/// Profile tab contents shared by the standalone guarded route and app shell.
class ProfileContent extends GetView<ProfileController> {
  const ProfileContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const LoadingState(message: 'Loading your profile');
      }
      final String? loadError = controller.loadError.value;
      if (loadError != null) {
        return ErrorState(message: loadError, onRetry: controller.loadProfile);
      }
      return const _ProfileForm();
    });
  }
}

class _ProfileForm extends GetView<ProfileController> {
  const _ProfileForm();

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return AppContent(
      maxWidth: 600,
      child: ListView(
        children: <Widget>[
          Text(
            'Personal details',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Form(
            key: controller.formKey,
            child: Column(
              children: <Widget>[
                AppTextField(
                  label: 'Full name',
                  controller: controller.fullNameController,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  validator: (String? value) =>
                      Validators.requiredField(value, 'name'),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Mobile (optional)',
                  controller: controller.mobileController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  validator: Validators.optionalMobile,
                  onFieldSubmitted: (_) => controller.saveProfile(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.email_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: const Text('Email'),
            subtitle: Text(controller.email),
          ),
          SubmitErrorMessage(controller.save),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => AppButton(
              label: 'Save changes',
              isLoading: controller.save.isBusy.value,
              onPressed: controller.saveProfile,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Security',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.lock_outline,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.toNamed<void>(AppRoutes.changePassword),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.logout,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: const Text('Sign out'),
            onTap: controller.signOut,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Danger zone', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Deleting your account removes all of your data permanently.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Delete account',
            icon: Icons.delete_forever_outlined,
            variant: AppButtonVariant.destructive,
            onPressed: () => Get.dialog<void>(const DeleteAccountDialog()),
          ),
        ],
      ),
    );
  }
}
