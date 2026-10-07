import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Welcome screen for signed-out users: short intro pages, then sign up or
/// sign in. Page position is local UI state, so no controller.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  static const List<_OnboardingPage> _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Know Where Your Money Goes',
      description:
          'See income and expenses across cash, bank and UPI in one place.',
    ),
    _OnboardingPage(
      icon: Icons.currency_rupee,
      title: 'Track Every Rupee',
      description:
          'Add a transaction in seconds and always know your current balance.',
    ),
    _OnboardingPage(
      icon: Icons.notifications_active_outlined,
      title: 'Stay Ahead of Your Payments',
      description:
          'Keep a khata of who owes you and whom you owe, with reminders '
          'before they are due.',
    ),
  ];

  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.maxContentWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: PageView(
                      onPageChanged: (int page) =>
                          setState(() => _currentPage = page),
                      children: _pages,
                    ),
                  ),
                  _PageDots(count: _pages.length, current: _currentPage),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: 'Get started',
                    onPressed: () => Get.toNamed<void>(AppRoutes.register),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => Get.toNamed<void>(AppRoutes.login),
                    child: const Text('I already have an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 72, color: colors.onPrimaryContainer),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          title,
          textAlign: TextAlign.center,
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          description,
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int index = 0; index < count; index++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              width: index == current ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: index == current
                    ? colors.primary
                    : colors.outlineVariant,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
        ],
      ),
    );
  }
}
