import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Shared frame for the auth screens: headline, supporting text and content,
/// scrollable above the keyboard and width-limited on tablets.
class AuthFormLayout extends StatelessWidget {
  const AuthFormLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.maxContentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    title,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(subtitle, style: textTheme.bodyLarge),
                  const SizedBox(height: AppSpacing.lg),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
