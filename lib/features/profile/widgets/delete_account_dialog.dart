import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/validators.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_dialog.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Confirms permanent account deletion. The password is required both as a
/// deliberate confirmation step and because the server only deletes right
/// after a password sign-in.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final ProfileController _controller = Get.find<ProfileController>();

  @override
  void initState() {
    super.initState();
    _controller.deletion.error.value = null;
  }

  // Never pops on success: deletion signs out, and AuthController replaces
  // every route (this dialog included) with sign-in. Popping as well would
  // remove the new sign-in route.
  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;
    await _controller.deleteAccount(_passwordController.text);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: 'Delete your account?',
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'This permanently deletes your profile, accounts, transactions '
                'and khata records. It cannot be undone.',
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Password',
                obscureText: true,
                autofocus: true,
                controller: _passwordController,
                textInputAction: TextInputAction.done,
                validator: (String? value) =>
                    Validators.requiredField(value, 'password'),
                onFieldSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: AppSpacing.md),
              SubmitErrorMessage(_controller.deletion),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        Obx(
          () => TextButton(
            onPressed: _controller.deletion.isBusy.value
                ? null
                : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        Obx(
          () => AppButton(
            label: 'Delete account',
            variant: AppButtonVariant.destructive,
            isExpanded: false,
            isLoading: _controller.deletion.isBusy.value,
            onPressed: _confirm,
          ),
        ),
      ],
    );
  }
}
