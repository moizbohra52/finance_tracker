import 'dart:typed_data';

import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/profile/widgets/delete_account_dialog.dart';
import 'package:finance_tracker/features/profile/widgets/profile_avatar.dart';
import 'package:finance_tracker/features/settings/widgets/settings_widgets.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class ProfileView extends GetView<ProfileController> {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppAppBar(title: 'Profile'),
      body: SafeArea(child: ProfileContent()),
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

class _ProfileForm extends StatelessWidget {
  const _ProfileForm();

  Future<void> _changePhoto(ProfileController controller) async {
    // Scaled down at pick time: the photo is shown small, and the size limit
    // is then easy to meet.
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    final Uint8List bytes = await picked.readAsBytes();
    await controller.uploadAvatar(picked.name, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final ProfileController controller = Get.find();
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    // Not a lazy list: a field scrolled out of a lazy list is unbuilt, and
    // its validation message goes with it. The profile is short, so every
    // field stays built.
    return AppContent(
      maxWidth: AppSizes.maxContentWidth + 180,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Obx(
                () => Semantics(
                  button: true,
                  label: controller.avatarLink.value == null
                      ? 'Add a profile photo'
                      : 'Change profile photo',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: controller.avatarBusy.value
                        ? null
                        : () => _changePhoto(controller),
                    child: ProfileAvatar(
                      initial: _initial(controller.displayName.value),
                      link: controller.avatarLink.value,
                      busy: controller.avatarBusy.value,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Obx(
                () => Text(
                  controller.avatarLink.value == null
                      ? 'Add a photo'
                      : 'Tap to change photo',
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Obx(() {
              final String? error = controller.avatarError.value;
              if (error == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: InlineMessage(message: error),
              );
            }),
            const SizedBox(height: AppSpacing.lg),
            const SettingsSectionTitle('Personal details'),
            const SizedBox(height: AppSpacing.sm),
            Form(
              key: controller.formKey,
              child: AppCard(
                child: Column(
                  children: <Widget>[
                    AppTextField(
                      label: 'Full name',
                      controller: controller.fullNameController,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      validator: Validators.profileName,
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
            ),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Column(
                children: <Widget>[
                  SettingsTile(
                    icon: Icons.email_outlined,
                    title: 'Email',
                    value: controller.email,
                  ),
                  Obx(
                    () => SettingsTile(
                      icon: Icons.schedule_outlined,
                      title: 'Time zone',
                      value: controller.timezone.value.isEmpty
                          ? 'Not available'
                          : controller.timezone.value,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your email and time zone are managed by your account and device.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            SubmitErrorMessage(controller.save),
            const SizedBox(height: AppSpacing.md),
            Obx(
              () => AppButton(
                label: 'Save changes',
                isLoading: controller.save.isBusy.value,
                onPressed: controller.saveProfile,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SettingsSectionTitle('Security'),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Column(
                children: <Widget>[
                  SettingsTile(
                    icon: Icons.lock_outline,
                    title: 'Change password',
                    onTap: () => Get.toNamed<void>(AppRoutes.changePassword),
                  ),
                  SettingsTile(
                    icon: Icons.logout_rounded,
                    title: 'Sign out',
                    onTap: controller.signOut,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SettingsSectionTitle('Danger zone', destructive: true),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Deleting your account permanently removes your profile, '
                    'accounts, transactions, khata records, reminders and photo. '
                    'This cannot be undone.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Delete account',
                    icon: Icons.delete_forever_outlined,
                    variant: AppButtonVariant.destructive,
                    onPressed: () =>
                        Get.dialog<void>(const DeleteAccountDialog()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initial(String name) {
    final String trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed[0].toUpperCase();
  }
}
