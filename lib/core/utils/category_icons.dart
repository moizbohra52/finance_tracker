import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter/material.dart';

/// Maps the stable icon keys stored on categories (see the seed migration)
/// to Material icons.
abstract final class CategoryIcons {
  static const Map<String, IconData> _byKey = <String, IconData>{
    'salary': Icons.payments_outlined,
    'business': Icons.storefront_outlined,
    'freelance': Icons.laptop_mac_outlined,
    'interest': Icons.savings_outlined,
    'gift': Icons.card_giftcard_outlined,
    'refund': Icons.assignment_return_outlined,
    'other_income': Icons.add_card_outlined,
    'food': Icons.restaurant_outlined,
    'groceries': Icons.shopping_basket_outlined,
    'transport': Icons.directions_bus_outlined,
    'fuel': Icons.local_gas_station_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'rent': Icons.home_outlined,
    'utilities': Icons.receipt_long_outlined,
    'mobile': Icons.phone_android_outlined,
    'emi': Icons.account_balance_outlined,
    'insurance': Icons.shield_outlined,
    'health': Icons.medical_services_outlined,
    'education': Icons.school_outlined,
    'entertainment': Icons.movie_outlined,
    'travel': Icons.flight_outlined,
    'subscriptions': Icons.subscriptions_outlined,
    'personal_care': Icons.spa_outlined,
    'donation': Icons.volunteer_activism_outlined,
    'other_expense': Icons.more_horiz,
  };

  /// The category's icon, or one that matches the transaction [type].
  static IconData of(String? key, TransactionType type) =>
      _byKey[key] ?? forType(type);

  static IconData forType(TransactionType type) => switch (type) {
    TransactionType.income => Icons.south_west_rounded,
    TransactionType.expense => Icons.north_east_rounded,
    TransactionType.transfer_in ||
    TransactionType.transfer_out => Icons.swap_horiz_rounded,
    TransactionType.payment_received => Icons.call_received_rounded,
    TransactionType.payment_made => Icons.call_made_rounded,
    TransactionType.adjustment_in ||
    TransactionType.adjustment_out => Icons.tune_rounded,
    TransactionType.opening_balance => Icons.flag_outlined,
  };
}

/// Presentation helpers for [TransactionType].
extension TransactionTypeLabel on TransactionType {
  String get label => switch (this) {
    TransactionType.income => 'Income',
    TransactionType.expense => 'Expense',
    TransactionType.transfer_in => 'Transfer in',
    TransactionType.transfer_out => 'Transfer out',
    TransactionType.adjustment_in => 'Adjustment in',
    TransactionType.adjustment_out => 'Adjustment out',
    TransactionType.opening_balance => 'Opening balance',
    TransactionType.payment_received => 'Payment received',
    TransactionType.payment_made => 'Payment made',
  };

  /// Whether this type adds to an account balance.
  bool get isInflow => switch (this) {
    TransactionType.income ||
    TransactionType.transfer_in ||
    TransactionType.adjustment_in ||
    TransactionType.payment_received => true,
    _ => false,
  };
}
