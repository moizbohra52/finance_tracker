import 'package:flutter/foundation.dart';

/// An account that is signed in on this device. Several can be at once and
/// one of them is active, like the account switcher of a social app.
///
/// "Login", not "account": in this app an account is a cash/bank/UPI
/// account. This holds no secret; the session itself stays in
/// SavedLoginStore.
@immutable
class SavedLogin {
  const SavedLogin({
    required this.userId,
    required this.email,
    required this.lastUsedAt,
    this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String email;

  /// The profile name when it was last known, or null.
  final String? displayName;

  /// The profile image URL or local cached path, or null.
  final String? avatarUrl;

  /// When the user last switched to (or signed in to) this account. The most
  /// recent one is the next active account after a sign-out.
  final DateTime lastUsedAt;

  /// Profile name, else the email's local part, so the switcher never shows a
  /// blank row.
  String get label {
    final String name = displayName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final String local = email.split('@').first.trim();
    return local.isNotEmpty ? local : email;
  }

  /// First letter of [label] for the fallback avatar.
  String get initial {
    final String text = label.trim();
    return text.isEmpty
        ? ''
        : String.fromCharCode(text.runes.first).toUpperCase();
  }

  SavedLogin copyWith({
    String? email,
    String? displayName,
    String? avatarUrl,
    DateTime? lastUsedAt,
  }) => SavedLogin(
    userId: userId,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedLogin &&
      other.userId == userId &&
      other.email == email &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode =>
      Object.hash(userId, email, displayName, avatarUrl, lastUsedAt);

  @override
  String toString() => 'SavedLogin($userId)';
}
