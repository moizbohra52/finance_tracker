import 'package:decimal/decimal.dart';

/// How an expense is divided: equal shares among ticked members, exact
/// amounts, percentages or share counts (stored as its `name`).
enum SplitMode { equal, exact, percent, shares }

/// A group of friends who share expenses, e.g. a trip or a flat.
class SplitGroup {
  const SplitGroup({
    required this.id,
    required this.userId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.avatarPath,
  });

  final String id;
  final String userId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The photo's object name in the avatars bucket (PhotoStore), or null.
  final String? avatarPath;

  bool get isLive => deletedAt == null;

  SplitGroup copyWith({
    String? name,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return SplitGroup(
      id: id,
      userId: userId,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      avatarPath: avatarPath,
    );
  }
}

/// One person in a group. A null [contactId] is the user themself; every
/// group has exactly one such member.
class SplitMember {
  const SplitMember({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.contactId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String groupId;

  /// The khata contact of the friend; null for the user's own member.
  final String? contactId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isMe => contactId == null;

  bool get isLive => deletedAt == null;

  SplitMember copyWith({DateTime? updatedAt, DateTime? deletedAt}) {
    return SplitMember(
      id: id,
      userId: userId,
      groupId: groupId,
      contactId: contactId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// A bill shared inside a group. Category and account are for the user's own
/// derived rows; when they are required is [SplitCalculator.validate].
class SplitExpense {
  const SplitExpense({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.title,
    required this.totalAmount,
    required this.expenseDate,
    required this.splitMode,
    required this.categoryId,
    required this.accountId,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String groupId;
  final String title;
  final Decimal totalAmount;
  final DateTime expenseDate;
  final SplitMode splitMode;

  /// Null when the user's own share is zero (they only paid for others).
  final String? categoryId;

  /// Null when the user neither paid nor shares this expense.
  final String? accountId;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;

  SplitExpense copyWith({
    String? title,
    Decimal? totalAmount,
    DateTime? expenseDate,
    SplitMode? splitMode,
    String? categoryId,
    String? accountId,
    String? note,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return SplitExpense(
      id: id,
      userId: userId,
      groupId: groupId,
      title: title ?? this.title,
      totalAmount: totalAmount ?? this.totalAmount,
      expenseDate: expenseDate ?? this.expenseDate,
      splitMode: splitMode ?? this.splitMode,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// One member's side of one expense: what they paid and what their share is.
/// [shareInput] is the percent or share count typed, so the form reopens in
/// the same mode.
class SplitPart {
  const SplitPart({
    required this.id,
    required this.userId,
    required this.splitExpenseId,
    required this.memberId,
    required this.paidAmount,
    required this.shareAmount,
    required this.createdAt,
    required this.updatedAt,
    this.shareInput,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String splitExpenseId;
  final String memberId;
  final Decimal paidAmount;
  final Decimal shareAmount;
  final Decimal? shareInput;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;

  SplitPart copyWith({
    Decimal? paidAmount,
    Decimal? shareAmount,
    Decimal? shareInput,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return SplitPart(
      id: id,
      userId: userId,
      splitExpenseId: splitExpenseId,
      memberId: memberId,
      paidAmount: paidAmount ?? this.paidAmount,
      shareAmount: shareAmount ?? this.shareAmount,
      shareInput: shareInput ?? this.shareInput,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// Money moved between two members of a group that is not an expense share.
class SplitSettlement {
  const SplitSettlement({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    required this.settledAt,
    required this.createdAt,
    required this.updatedAt,
    this.accountId,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String groupId;

  /// The member who paid; reduces what they owe.
  final String fromMemberId;

  /// The member who received.
  final String toMemberId;
  final Decimal amount;
  final DateTime settledAt;

  /// Only a settlement with the user can use an account.
  final String? accountId;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;

  SplitSettlement copyWith({
    Decimal? amount,
    DateTime? settledAt,
    String? accountId,
    String? note,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return SplitSettlement(
      id: id,
      userId: userId,
      groupId: groupId,
      fromMemberId: fromMemberId,
      toMemberId: toMemberId,
      amount: amount ?? this.amount,
      settledAt: settledAt ?? this.settledAt,
      accountId: accountId ?? this.accountId,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
