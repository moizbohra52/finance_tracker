import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/split.dart';

/// Row mapping for public.split_groups.
abstract final class SplitGroupModel {
  /// Rows written locally and payloads sent to the server carry no timestamps
  /// (the clock/trigger sets them), so parsing accepts them missing.
  static DateTime _when(dynamic v) => v == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.parse(v as String);

  /// avatar_url is read but never in toJson: only SplitRepository.setGroupPhoto
  /// writes it, so a group edit (or a server without the column) leaves it.
  static SplitGroup fromJson(Map<String, dynamic> json) => SplitGroup(
    id: json['id'] as String,
    userId: (json['user_id'] ?? '') as String,
    name: json['name'] as String,
    createdAt: _when(json['created_at']),
    updatedAt: _when(json['updated_at']),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
    avatarPath: json['avatar_url'] as String?,
  );

  static Map<String, dynamic> toJson(SplitGroup g) => <String, dynamic>{
    'id': g.id,
    'user_id': g.userId,
    'name': g.name,
  };
}

/// Row mapping for public.split_group_members.
abstract final class SplitMemberModel {
  /// Rows written locally and payloads sent to the server carry no timestamps
  /// (the clock/trigger sets them), so parsing accepts them missing.
  static DateTime _when(dynamic v) => v == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.parse(v as String);

  static SplitMember fromJson(Map<String, dynamic> json) => SplitMember(
    id: json['id'] as String,
    userId: (json['user_id'] ?? '') as String,
    groupId: json['group_id'] as String,
    // Null is the user's own member.
    contactId: json['contact_id'] as String?,
    createdAt: _when(json['created_at']),
    updatedAt: _when(json['updated_at']),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
  );

  static Map<String, dynamic> toJson(SplitMember m) => <String, dynamic>{
    'id': m.id,
    'user_id': m.userId,
    'group_id': m.groupId,
    'contact_id': m.contactId,
  };
}

/// Row mapping for public.split_expenses.
abstract final class SplitExpenseModel {
  /// Rows written locally and payloads sent to the server carry no timestamps
  /// (the clock/trigger sets them), so parsing accepts them missing.
  static DateTime _when(dynamic v) => v == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.parse(v as String);

  static SplitExpense fromJson(Map<String, dynamic> json) => SplitExpense(
    id: json['id'] as String,
    userId: (json['user_id'] ?? '') as String,
    groupId: json['group_id'] as String,
    title: json['title'] as String,
    totalAmount: Decimal.parse(json['total_amount'].toString()),
    expenseDate: DateTime.parse(json['expense_date'] as String).toLocal(),
    splitMode: SplitMode.values.byName(json['split_mode'] as String),
    categoryId: json['category_id'] as String?,
    accountId: json['account_id'] as String?,
    note: json['note'] as String?,
    createdAt: _when(json['created_at']),
    updatedAt: _when(json['updated_at']),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
  );

  static Map<String, dynamic> toJson(SplitExpense e) => <String, dynamic>{
    'id': e.id,
    'user_id': e.userId,
    'group_id': e.groupId,
    'title': e.title,
    'total_amount': e.totalAmount.toString(),
    'expense_date': e.expenseDate.toUtc().toIso8601String(),
    'split_mode': e.splitMode.name,
    'category_id': e.categoryId,
    'account_id': e.accountId,
    'note': e.note,
  };
}

/// Row mapping for public.split_expense_parts.
abstract final class SplitPartModel {
  /// Rows written locally and payloads sent to the server carry no timestamps
  /// (the clock/trigger sets them), so parsing accepts them missing.
  static DateTime _when(dynamic v) => v == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.parse(v as String);

  static SplitPart fromJson(Map<String, dynamic> json) => SplitPart(
    id: json['id'] as String,
    userId: (json['user_id'] ?? '') as String,
    splitExpenseId: json['split_expense_id'] as String,
    memberId: json['member_id'] as String,
    paidAmount: Decimal.parse(json['paid_amount'].toString()),
    shareAmount: Decimal.parse(json['share_amount'].toString()),
    shareInput: json['share_input'] == null
        ? null
        : Decimal.parse(json['share_input'].toString()),
    createdAt: _when(json['created_at']),
    updatedAt: _when(json['updated_at']),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
  );

  static Map<String, dynamic> toJson(SplitPart p) => <String, dynamic>{
    'id': p.id,
    'user_id': p.userId,
    'split_expense_id': p.splitExpenseId,
    'member_id': p.memberId,
    'paid_amount': p.paidAmount.toString(),
    'share_amount': p.shareAmount.toString(),
    'share_input': p.shareInput?.toString(),
  };
}

/// Row mapping for public.split_settlements.
abstract final class SplitSettlementModel {
  /// Rows written locally and payloads sent to the server carry no timestamps
  /// (the clock/trigger sets them), so parsing accepts them missing.
  static DateTime _when(dynamic v) => v == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.parse(v as String);

  static SplitSettlement fromJson(Map<String, dynamic> json) => SplitSettlement(
    id: json['id'] as String,
    userId: (json['user_id'] ?? '') as String,
    groupId: json['group_id'] as String,
    fromMemberId: json['from_member_id'] as String,
    toMemberId: json['to_member_id'] as String,
    amount: Decimal.parse(json['amount'].toString()),
    settledAt: DateTime.parse(json['settled_at'] as String).toLocal(),
    accountId: json['account_id'] as String?,
    note: json['note'] as String?,
    createdAt: _when(json['created_at']),
    updatedAt: _when(json['updated_at']),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
  );

  static Map<String, dynamic> toJson(SplitSettlement s) => <String, dynamic>{
    'id': s.id,
    'user_id': s.userId,
    'group_id': s.groupId,
    'from_member_id': s.fromMemberId,
    'to_member_id': s.toMemberId,
    'amount': s.amount.toString(),
    'settled_at': s.settledAt.toUtc().toIso8601String(),
    'account_id': s.accountId,
    'note': s.note,
  };
}
