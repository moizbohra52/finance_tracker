import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/features/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';

/// About the app: version and open-source licences.
class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const AppAppBar(title: 'About'),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 180,
          child: ListView(
            children: <Widget>[
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Text(
                  AppConstants.appName,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Text(
                  'Version ${AppConstants.appVersion}',
                  style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SettingsCard(
                children: <Widget>[
                  SettingsTile(
                    icon: Icons.article_outlined,
                    title: 'Open-source licences',
                    subtitle: 'Libraries this app is built with',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: AppConstants.appName,
                      applicationVersion: AppConstants.appVersion,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A legal page. The text is a placeholder until the policy is published, and
/// it says so, rather than presenting draft wording as final.
class PolicyView extends StatelessWidget {
  const PolicyView({super.key, required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppAppBar(title: title),
      body: SafeArea(
        child: AppContent(
          maxWidth: AppSizes.maxContentWidth + 180,
          child: ListView(
            children: <Widget>[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final String paragraph in paragraphs) ...<Widget>[
                      Text(paragraph, style: text.bodyMedium),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
