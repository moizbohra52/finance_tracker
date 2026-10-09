import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/theme/finance_colors.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:flutter/material.dart';

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
    return Row(
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
            ),
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
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
  });

  final Decimal currentBalance;
  final Decimal openingBalance;
  final Decimal monthIncome;
  final Decimal monthExpense;
  final bool isHidden;
  final VoidCallback onToggleHidden;

  static const String _mask = '••••••';

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final HSLColor hsl = HSLColor.fromColor(colors.primary);
    final Color primaryDark = hsl
        .withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0))
        .toColor();

    String show(Decimal value) => isHidden ? _mask : AppFormatters.money(value);

    return Semantics(
      container: true,
      label: 'Current balance ${show(currentBalance)}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: LinearGradient(
            colors: <Color>[colors.primary, primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: colors.onPrimary.withValues(alpha: 0.16),
            width: 1.2,
          ),
        ),
        child: ClipRRect(
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
                    color: colors.onPrimary.withValues(alpha: 0.05),
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
                            color: colors.onPrimary.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Current balance',
                            style: text.labelLarge?.copyWith(
                              color: colors.onPrimary.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: colors.onPrimary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            tooltip: isHidden ? 'Show balance' : 'Hide balance',
                            color: colors.onPrimary,
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
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + 2,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.onPrimary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        'Opening balance ${show(openingBalance)}',
                        style: text.labelMedium?.copyWith(
                          color: colors.onPrimary.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
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
                              icon: Icons.arrow_downward_rounded,
                              iconColor: AppColors.incomeOnAccent,
                              label: 'Income this month',
                              value: show(monthIncome),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _CardFlow(
                              icon: Icons.arrow_upward_rounded,
                              iconColor: AppColors.expenseOnAccent,
                              label: 'Expense this month',
                              value: show(monthExpense),
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
    );
  }
}

class _CardFlow extends StatelessWidget {
  const _CardFlow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md - 2,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colors.onPrimary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: colors.onPrimary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.onPrimary.withValues(alpha: 0.16),
            ),
            child: Icon(icon, size: 18, color: iconColor),
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
                    color: colors.onPrimary.withValues(alpha: 0.8),
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
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: color, size: 16),
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
              const SizedBox(height: AppSpacing.xs + 2),
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
        ),
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
    final ColorScheme colors = Theme.of(context).colorScheme;
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
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: colors.primary, size: 24),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
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
      label: 'Loading',
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
    SkeletonType.transaction => _SkeletonCard(
      child: _SkeletonRow(base: base, squareLeading: true),
    ),
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

/// Icon, two text lines and an amount: the shape of most list rows.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({
    required this.base,
    this.leading = true,
    this.squareLeading = false,
  });

  final Color base;
  final bool leading;
  final bool squareLeading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (leading) ...<Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: base,
              shape: squareLeading ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: squareLeading
                  ? BorderRadius.circular(AppRadius.md)
                  : null,
            ),
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
