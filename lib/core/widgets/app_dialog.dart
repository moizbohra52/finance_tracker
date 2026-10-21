import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shared dialog shell for app-specific content and actions.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.icon,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      icon: icon,
      title: Text(title),
      content: content,
      actions: actions,
    );
  }
}

/// Asks before closing the application. Resolves to true only if the user confirms.
Future<bool> confirmExit(BuildContext context) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AppDialog(
      title: 'Exit App'.tr,
      icon: const Icon(Icons.exit_to_app_rounded),
      content: Text('Are you sure you want to exit the app?'.tr),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Exit'.tr),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
