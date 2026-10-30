import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Section title with an optional trailing text action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
              ),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// The home screen's headline number: current balance first, then opening
/// balance and this month's income and expense.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.currentBalance,
    required this.openingBalance,
    required this.monthIncome,
    required this.monthExpense,
    required this.isHidden,
    required this.onToggleHidden,
    this.onTap,
    this.onOpeningBalanceTap,
    this.onIncomeTap,
    this.onExpenseTap,
  });

  final Decimal currentBalance;
  final Decimal openingBalance;
  final Decimal monthIncome;
  final Decimal monthExpense;
  final bool isHidden;
  final VoidCallback onToggleHidden;
  final VoidCallback? onTap;
  final VoidCallback? onOpeningBalanceTap;
  final VoidCallback? onIncomeTap;
  final VoidCallback? onExpenseTap;

  static const String _mask = '••••••';

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    // Light mode paints the card in primary. Dark mode's primary is a pale
    // tone, so there the card uses primaryContainer, which stays a deep,
    // vivid colour that light text and the money colours read well on.
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color card = isDark ? colors.primaryContainer : colors.primary;
    final Color onCard = isDark ? colors.onPrimaryContainer : colors.onPrimary;
    final HSLColor hsl = HSLColor.fromColor(card);
    final Color primaryDark = hsl
        .withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0))
        .toColor();

    String show(Decimal value) => isHidden ? _mask : AppFormatters.money(value);

    return Semantics(
      container: true,
      label: 'Current balance @amount'.trParams(<String, String>{
        'amount': show(currentBalance),
      }),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: LinearGradient(
            colors: <Color>[card, primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: AppShadows.floating(card, alpha: 0.28),
          border: Border.all(color: onCard.withValues(alpha: 0.16), width: 1.2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    right: -30,
                    top: -30,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: onCard.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: onCard.withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Current balance'.tr,
                                style: text.labelLarge?.copyWith(
                                  color: onCard.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: onCard.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 20,
                                tooltip: isHidden
                                    ? 'Show balance'.tr
                                    : 'Hide balance'.tr,
                                color: onCard,
                                icon: Icon(
                                  isHidden
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: onToggleHidden,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            show(currentBalance),
                            style: text.displaySmall?.copyWith(
                              color: onCard,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onOpeningBalanceTap,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm + 2,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: onCard.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: Text(
                                'Opening balance @amount'.trParams(
                                  <String, String>{
                                    'amount': show(openingBalance),
                                  },
                                ),
                                style: text.labelMedium?.copyWith(
                                  color: onCard.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                child: _CardFlow(
                                  onCard: onCard,
                                  icon: Icons.arrow_downward_rounded,
                                  label: 'Income this month'.tr,
                                  value: show(monthIncome),
                                  onTap: onIncomeTap,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _CardFlow(
                                  onCard: onCard,
                                  icon: Icons.arrow_upward_rounded,
                                  label: 'Expense this month'.tr,
                                  value: show(monthExpense),
                                  onTap: onExpenseTap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

class _CardFlow extends StatelessWidget {
  const _CardFlow({
    required this.onCard,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  /// Text colour on the balance card.
  final Color onCard;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md - 2,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: onCard.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: onCard.withValues(alpha: 0.1), width: 1),
          ),
          child: Row(
            children: <Widget>[
              IconBadge(
                icon: icon,
                color: onCard,
                background: onCard.withValues(alpha: 0.16),
                size: AppSizes.iconBadgeSmall,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Wraps to a second line on narrow phones; a label cut to
                    // "Income this mo…" is worse than a taller tile.
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(
                        color: onCard.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: text.titleSmall?.copyWith(
                          color: onCard,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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

/// Compact label + amount tile with a tinted icon.
class SummaryTile extends StatelessWidget {
  const SummaryTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(
                icon: icon,
                color: color,
                size: AppSizes.iconBadgeSmall,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: text.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded icon button with a label underneath (home quick actions).
class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconBadge(icon: icon, size: AppSizes.quickAction),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card that points to a planning screen (budgets, recurring, reminders).
class PlanTile extends StatelessWidget {
  const PlanTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconBadge(icon: icon, size: AppSizes.iconBadgeSmall + AppSpacing.xs),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subtitle,
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// How a money amount reads in lists: sign + colour, never colour alone.
enum MoneyFlow { inflow, outflow, neutral }

class MoneyText extends StatelessWidget {
  const MoneyText(this.amount, {super.key, required this.flow, this.style});

  final Decimal amount;
  final MoneyFlow flow;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final FinanceColors money = FinanceColors.of(context);
    final (String text, Color? color) = switch (flow) {
      MoneyFlow.inflow => (
        AppFormatters.signedMoney(amount, positive: true),
        money.income,
      ),
      MoneyFlow.outflow => (
        AppFormatters.signedMoney(amount, positive: false),
        money.expense,
      ),
      MoneyFlow.neutral => (AppFormatters.money(amount), null),
    };
    return Text(
      text,
      style: (style ?? Theme.of(context).textTheme.titleSmall)?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Rounded progress bar that eases to its value. A NaN or out-of-range ratio
/// is clamped, so a bad calculation can never crash the frame.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final double target = value.isFinite ? value.clamp(0.0, 1.0) : 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppSizes.slowAnimation,
        curve: Curves.easeOutCubic,
        builder: (_, double animated, _) => LinearProgressIndicator(
          value: animated,
          minHeight: height,
          color: color,
          backgroundColor: color.withValues(alpha: 0.14),
        ),
      ),
    );
  }
}

/// Placeholder rows shown while the first page of a list loads. [type]
/// roughly matches the shape of the rows that replace it, so the layout does
/// not jump when data arrives.
class SkeletonList extends StatefulWidget {
  const SkeletonList({
    super.key,
    this.count = 6,
    this.type = SkeletonType.generic,
  });

  final int count;
  final SkeletonType type;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

enum SkeletonType { generic, transaction, account, khata, budget, report }

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final Widget item = _item(base);
    return Semantics(
      label: 'Loading'.tr,
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.4, end: 1).animate(_pulse),
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: widget.count,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, _) => item,
          ),
        ),
      ),
    );
  }

  Widget _item(Color base) => switch (widget.type) {
    SkeletonType.generic => _SkeletonRow(base: base),
    SkeletonType.transaction => _SkeletonCard(child: _SkeletonRow(base: base)),
    SkeletonType.account => _SkeletonCard(child: _SkeletonRow(base: base)),
    SkeletonType.khata => _SkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SkeletonRow(base: base, leading: false),
          const SizedBox(height: AppSpacing.sm),
          _SkeletonBar(base: base, width: 120, height: 10),
        ],
      ),
    ),
    SkeletonType.budget => _SkeletonCard(
      child: Column(
        children: <Widget>[
          _SkeletonRow(base: base, leading: false),
          const SizedBox(height: AppSpacing.md),
          _SkeletonBar(base: base, height: 6),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              _SkeletonBar(base: base, width: 70, height: 10),
              const Spacer(),
              _SkeletonBar(base: base, width: 70, height: 10),
            ],
          ),
        ],
      ),
    ),
    SkeletonType.report => _SkeletonCard(
      child: Column(
        children: <Widget>[
          _SkeletonRow(base: base, leading: false),
          const SizedBox(height: AppSpacing.md),
          _SkeletonBar(base: base, height: AppSizes.chartHeightSmall),
        ],
      ),
    ),
  };
}

/// Badge, two text lines and an amount: the shape of most list rows.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.base, this.leading = true});

  final Color base;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (leading) ...<Widget>[
          Container(
            width: AppSizes.iconBadge,
            height: AppSizes.iconBadge,
            decoration: BoxDecoration(color: base, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SkeletonBar(base: base, width: 140, height: 12),
              const SizedBox(height: AppSpacing.sm),
              _SkeletonBar(base: base, width: 90, height: 10),
            ],
          ),
        ),
        _SkeletonBar(base: base, width: 64, height: 14),
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.base,
    required this.height,
    this.width = double.infinity,
  });

  final Color base;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
  );
}
