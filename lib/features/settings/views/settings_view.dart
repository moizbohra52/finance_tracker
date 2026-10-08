import 'dart:async';

import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/theme/app_accent_color.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:finance_tracker/core/widgets/sync_status_sheet.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:finance_tracker/features/notifications/widgets/notification_settings_section.dart';
import 'package:finance_tracker/features/profile/widgets/delete_account_dialog.dart';
import 'package:finance_tracker/features/settings/controllers/settings_controller.dart';
import 'package:finance_tracker/features/settings/widgets/settings_widgets.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Appearance, region and format, notifications, security and information.
///
/// Appearance is kept on this device (it must apply before sign-in). Region and
/// format belong to the account and are saved to the server.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Settings'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxPageWidth,
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: const <Widget>[
              SizedBox(height: AppSpacing.md),
              SettingsSectionTitle('Appearance'),
              SizedBox(height: AppSpacing.sm),
              _AppearanceCard(),
              SizedBox(height: AppSpacing.lg),
              SettingsSectionTitle('Region and format'),
              SizedBox(height: AppSpacing.sm),
              _RegionSection(),
              SizedBox(height: AppSpacing.lg),
              NotificationSettingsSection(),
              SizedBox(height: AppSpacing.lg),
              SettingsSectionTitle('Security'),
              SizedBox(height: AppSpacing.sm),
              _SecuritySection(),
              SizedBox(height: AppSpacing.lg),
              SettingsSectionTitle('Information'),
              SizedBox(height: AppSpacing.sm),
              _InformationSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final ThemeController themeController = Get.find<ThemeController>();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
              onSelectionChanged: (Set<ThemeMode> selection) {
                unawaited(themeController.setThemeMode(selection.single));
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Logo colours', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _AccentWrap(
            accents: AppAccentColor.logoColours,
            controller: themeController,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('More colours', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _AccentWrap(
            accents: AppAccentColor.otherColours,
            controller: themeController,
          ),
        ],
      ),
    );
  }
}

class _AccentWrap extends StatelessWidget {
  const _AccentWrap({required this.accents, required this.controller});

  final List<AppAccentColor> accents;
  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final AppAccentColor accent in accents)
            _AccentChoice(
              accent: accent,
              selected: controller.accentColor.value == accent,
              onSelected: () => unawaited(controller.setAccentColor(accent)),
            ),
        ],
      ),
    );
  }
}

class _AccentChoice extends StatelessWidget {
  const _AccentChoice({
    required this.accent,
    required this.selected,
    required this.onSelected,
  });

  final AppAccentColor accent;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: '${accent.label} accent',
      child: ChoiceChip(
        avatar: CircleAvatar(
          radius: 9,
          backgroundColor: accent.seedColor,
          child: selected
              ? Icon(Icons.check, size: 12, color: colors.onPrimary)
              : null,
        ),
        label: Text(accent.label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

/// Currency, date and number formats, first day of the week, language and
/// default account. Each row opens a list; a choice is saved at once.
class _RegionSection extends GetView<SettingsController> {
  const _RegionSection();

  Future<void> _change(BuildContext context, UserPreferences next) async {
    final bool saved = await controller.savePreferences(next);
    if (saved) AppSnackbar.show('Settings saved.');
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const AppCard(
          child: LoadingState(message: 'Loading your settings'),
        );
      }
      final String? loadError = controller.loadError.value;
      if (loadError != null) {
        return AppCard(
          child: ErrorState(message: loadError, onRetry: controller.load),
        );
      }
      final UserPreferences prefs = controller.preferences.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SubmitErrorMessage(controller.save),
          SettingsCard(
            children: <Widget>[
              SettingsTile(
                icon: Icons.payments_outlined,
                title: 'Currency',
                value: _currencyLabel(prefs.currencyCode),
                onTap: () => _pickCurrency(context, prefs),
              ),
              SettingsTile(
                icon: Icons.calendar_today_outlined,
                title: 'Date format',
                value: prefs.dateStyle.example,
                onTap: () => _pickDateStyle(context, prefs),
              ),
              SettingsTile(
                icon: Icons.format_list_numbered_rtl_rounded,
                title: 'Number format',
                value: prefs.numberStyle.example,
                onTap: () => _pickNumberStyle(context, prefs),
              ),
              SettingsTile(
                icon: Icons.view_week_outlined,
                title: 'First day of the week',
                value: prefs.weekStart.label,
                onTap: () => _pickWeekStart(context, prefs),
              ),
              SettingsTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Default account',
                subtitle: 'Pre-selected on new transactions',
                value: _accountName(prefs.defaultAccountId),
                onTap: () => _pickDefaultAccount(context, prefs),
              ),
              const SettingsTile(
                icon: Icons.translate_rounded,
                title: 'Language',
                subtitle: 'More languages are coming',
                value: 'English',
              ),
            ],
          ),
        ],
      );
    });
  }

  String _currencyLabel(String code) {
    final CurrencyOption option = Currencies.byCode(code);
    return '${option.code} · ${AppFormatters.currency(1234.5, currencyCode: option.code)}';
  }

  String _accountName(String? id) {
    if (id == null) return 'First account';
    for (final Account account in controller.accounts) {
      if (account.id == id) return account.name;
    }
    return 'First account';
  }

  Future<void> _pickCurrency(
    BuildContext context,
    UserPreferences prefs,
  ) async {
    final CurrencyOption? choice = await showChoiceSheet<CurrencyOption>(
      context,
      title: 'Currency',
      options: Currencies.supported,
      selected: Currencies.byCode(prefs.currencyCode),
      labelOf: (CurrencyOption o) => '${o.name} (${o.code})',
      detailOf: (CurrencyOption o) =>
          AppFormatters.currency(1234.5, currencyCode: o.code),
    );
    if (choice != null && context.mounted) {
      await _change(context, prefs.copyWith(currencyCode: choice.code));
    }
  }

  Future<void> _pickDateStyle(
    BuildContext context,
    UserPreferences prefs,
  ) async {
    final DateStyle? choice = await showChoiceSheet<DateStyle>(
      context,
      title: 'Date format',
      options: DateStyle.values,
      selected: prefs.dateStyle,
      labelOf: (DateStyle s) => s.example,
    );
    if (choice != null && context.mounted) {
      await _change(context, prefs.copyWith(dateStyle: choice));
    }
  }

  Future<void> _pickNumberStyle(
    BuildContext context,
    UserPreferences prefs,
  ) async {
    final NumberStyle? choice = await showChoiceSheet<NumberStyle>(
      context,
      title: 'Number format',
      options: NumberStyle.values,
      selected: prefs.numberStyle,
      labelOf: (NumberStyle s) => s.example,
      detailOf: (NumberStyle s) => s == NumberStyle.indian
          ? 'Lakh grouping, as used in India'
          : 'Thousands grouping',
    );
    if (choice != null && context.mounted) {
      await _change(context, prefs.copyWith(numberStyle: choice));
    }
  }

  Future<void> _pickWeekStart(
    BuildContext context,
    UserPreferences prefs,
  ) async {
    final WeekStart? choice = await showChoiceSheet<WeekStart>(
      context,
      title: 'First day of the week',
      options: WeekStart.values,
      selected: prefs.weekStart,
      labelOf: (WeekStart s) => s.label,
    );
    if (choice != null && context.mounted) {
      await _change(context, prefs.copyWith(weekStart: choice));
    }
  }

  /// "First account" is an option of its own, so dismissing the sheet (null)
  /// and choosing it (an option with a null id) stay distinct.
  Future<void> _pickDefaultAccount(
    BuildContext context,
    UserPreferences prefs,
  ) async {
    final List<_AccountOption> options = <_AccountOption>[
      const _AccountOption(null, 'First account'),
      for (final Account account in controller.accounts)
        _AccountOption(account.id, account.name),
    ];
    final _AccountOption selected = options.firstWhere(
      (_AccountOption o) => o.id == prefs.defaultAccountId,
      orElse: () => options.first,
    );
    final _AccountOption? choice = await showChoiceSheet<_AccountOption>(
      context,
      title: 'Default account',
      options: options,
      selected: selected,
      labelOf: (_AccountOption o) => o.name,
    );
    if (choice != null && context.mounted) {
      await _change(
        context,
        prefs.copyWith(
          defaultAccountId: choice.id,
          clearDefaultAccount: choice.id == null,
        ),
      );
    }
  }
}

/// One row of the default-account choice. [id] is null for "First account".
class _AccountOption {
  const _AccountOption(this.id, this.name);

  final String? id;
  final String name;

  @override
  bool operator ==(Object other) => other is _AccountOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Sign-out and account deletion, both reachable from here as well as from
/// the profile.
class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: <Widget>[
        SettingsTile(
          icon: Icons.lock_outline,
          title: 'Change password',
          onTap: () => Get.toNamed<void>(AppRoutes.changePassword),
        ),
        SettingsTile(
          icon: Icons.logout_rounded,
          title: 'Sign out of this device',
          onTap: () => Get.find<AuthController>().signOut(),
        ),
        SettingsTile(
          icon: Icons.delete_forever_outlined,
          title: 'Delete account',
          subtitle: 'Permanently removes your data',
          destructive: true,
          onTap: () => Get.dialog<void>(const DeleteAccountDialog()),
        ),
      ],
    );
  }
}

class _InformationSection extends StatelessWidget {
  const _InformationSection();

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: <Widget>[
        SettingsTile(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy policy',
          onTap: () => Get.toNamed<void>(AppRoutes.privacyPolicy),
        ),
        SettingsTile(
          icon: Icons.description_outlined,
          title: 'Terms of service',
          onTap: () => Get.toNamed<void>(AppRoutes.terms),
        ),
        SettingsTile(
          icon: Icons.sync_rounded,
          title: 'Cloud sync',
          subtitle: 'Sync queue & connection status',
          onTap: () => showSyncStatusSheet(context),
        ),
        SettingsTile(
          icon: Icons.info_outline_rounded,
          title: 'About',
          value: 'Version ${AppConstants.appVersion}',
          onTap: () => Get.toNamed<void>(AppRoutes.about),
        ),
      ],
    );
  }
}
