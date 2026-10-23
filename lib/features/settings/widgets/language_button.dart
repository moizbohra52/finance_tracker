import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:finance_tracker/features/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The language choice on the signed-out screens. Shows the current language
/// in its own script, so anyone can find theirs.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = Get.find<SettingsController>();
    return Obx(() {
      final AppLanguage current = settings.preferences.value.language;
      return Tooltip(
        message: 'Language'.tr,
        child: TextButton.icon(
          icon: const Icon(Icons.translate),
          label: Text(current.label),
          onPressed: () async {
            final AppLanguage? choice = await showChoiceSheet<AppLanguage>(
              context,
              title: 'Language'.tr,
              options: AppLanguage.values,
              selected: current,
              labelOf: (AppLanguage l) => l.label,
            );
            if (choice != null) settings.chooseLanguage(choice);
          },
        ),
      );
    });
  }
}
