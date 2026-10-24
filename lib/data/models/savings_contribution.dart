import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';

/// Row mapping for public.savings_contributions.
abstract final class SavingsContributionModel {
  static SavingsContribution fromJson(Map<String, dynamic> json) =>
      SavingsContribution(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        transactionId: json['transaction_id'] as String,
        goalId: json['goal_id'] as String,
        amount: Decimal.parse(json['amount'].toString()),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String),
      );

  static Map<String, dynamic> toJson(SavingsContribution c) =>
      <String, dynamic>{
        'id': c.id,
        'user_id': c.userId,
        'transaction_id': c.transactionId,
        'goal_id': c.goalId,
        'amount': c.amount.toString(),
      };
}
