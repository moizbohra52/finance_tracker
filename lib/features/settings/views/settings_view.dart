import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Phase 00 settings screen: appearance only. Full settings arrive in
/// Phase 10.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController themeController = Get.find<ThemeController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: <Widget>[
            Text('Appearance', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Obx(
              () => SegmentedButton<ThemeMode>(
                segments: const <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('System'),
                  ),
                ],
                selected: <ThemeMode>{themeController.themeMode.value},
                onSelectionChanged: (Set<ThemeMode> selection) =>
                    themeController.setThemeMode(selection.single),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
