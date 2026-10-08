import 'dart:async';

import 'package:finance_tracker/core/theme/app_accent_color.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/features/notifications/widgets/notification_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Appearance and notification settings. Full account and finance settings
/// arrive in Phase 10.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController themeController = Get.find<ThemeController>();

    return Scaffold(
      appBar: const AppAppBar(title: 'Settings'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxPageWidth,
          child: ListView(
            children: <Widget>[
              Text('Appearance', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Obx(
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
                    onSelectionChanged: (Set<ThemeMode> selection) {
                      unawaited(themeController.setThemeMode(selection.single));
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Accent color',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Obx(
                  () => Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: AppAccentColor.values.map((
                      AppAccentColor accent,
                    ) {
                      final bool isSelected =
                          themeController.accentColor.value == accent;
                      return Tooltip(
                        message: '${accent.label} accent',
                        child: ChoiceChip(
                          avatar: CircleAvatar(
                            radius: 9,
                            backgroundColor: accent.seedColor,
                            child: isSelected
                                ? Icon(
                                    Icons.check,
                                    size: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                  )
                                : null,
                          ),
                          label: Text(accent.label),
                          selected: isSelected,
                          onSelected: (_) =>
                              unawaited(themeController.setAccentColor(accent)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const NotificationSettingsSection(),
            ],
          ),
        ),
      ),
    );
  }
}
