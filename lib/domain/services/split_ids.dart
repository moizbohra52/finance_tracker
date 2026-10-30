import 'package:uuid/uuid.dart';

/// Deterministic uuid v5 ids for split rows and their derived rows, so every
/// device and every retry writes the same row (pattern of
/// `budget_calculator.dart`).
abstract final class SplitIds {
  /// `split-member:<group id>:<contact id | me>`; the user's own member uses
  /// `me` because their contact id is null.
  static String member(String groupId, String? contactId) =>
      _v5('split-member:$groupId:${contactId ?? 'me'}');

  /// `split-part:<expense id>:<member id>`.
  static String part(String expenseId, String memberId) =>
      _v5('split-part:$expenseId:$memberId');

  /// The user's expense transaction for their own share.
  static String expenseShare(String expenseId) =>
      _v5('split-expense:$expenseId:share');

  /// The user's payment_made / payment_received transaction for the money
  /// they put up for others (or had put up for them).
  static String expenseBalance(String expenseId) =>
      _v5('split-expense:$expenseId:balance');

  /// The khata entry for the user's net with one contact on one expense.
  static String expenseContact(String expenseId, String contactId) =>
      _v5('split-expense:$expenseId:contact:$contactId');

  /// The khata payment a settlement with the user writes.
  static String settlementKhata(String settlementId) =>
      _v5('split-settlement:$settlementId:khata');

  /// The account movement of a settlement with the user and an account.
  static String settlementAccount(String settlementId) =>
      _v5('split-settlement:$settlementId:account');

  static String _v5(String name) => const Uuid().v5(Namespace.url.value, name);
}
