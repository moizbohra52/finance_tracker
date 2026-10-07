import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Semantic money colours, resolved per brightness through the theme.
///
/// Colour must never be the only signal: pair it with a sign, icon or label
/// (see docs/06_UI_UX_GUIDELINES.md, Accessibility).
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.income,
    required this.expense,
    required this.receivable,
    required this.payable,
  });

  final Color income;
  final Color expense;
  final Color receivable;
  final Color payable;

  static const FinanceColors light = FinanceColors(
    income: AppColors.incomeLight,
    expense: AppColors.expenseLight,
    receivable: AppColors.receivableLight,
    payable: AppColors.payableLight,
  );

  static const FinanceColors dark = FinanceColors(
    income: AppColors.incomeDark,
    expense: AppColors.expenseDark,
    receivable: AppColors.receivableDark,
    payable: AppColors.payableDark,
  );

  /// AppTheme registers this extension on both themes, so it is always present.
  static FinanceColors of(BuildContext context) =>
      Theme.of(context).extension<FinanceColors>()!;

  @override
  FinanceColors copyWith({
    Color? income,
    Color? expense,
    Color? receivable,
    Color? payable,
  }) {
    return FinanceColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      receivable: receivable ?? this.receivable,
      payable: payable ?? this.payable,
    );
  }

  @override
  FinanceColors lerp(FinanceColors? other, double t) {
    if (other == null) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      receivable: Color.lerp(receivable, other.receivable, t)!,
      payable: Color.lerp(payable, other.payable, t)!,
    );
  }
}
