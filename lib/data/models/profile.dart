import 'package:flutter/foundation.dart';

/// The signed-in user's row in public.profiles.
///
/// [avatarPath] is the object path in the private `avatars` bucket, not a URL
/// (the column keeps its name avatar_url). Turn it into a short-lived link
/// with ProfileRepository.avatarLink before showing it.
@immutable
class Profile {
  const Profile({
    required this.id,
    this.fullName,
    this.mobile,
    this.avatarPath,
    this.currencyCode,
    this.timezone,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    fullName: json['full_name'] as String?,
    mobile: json['mobile'] as String?,
    avatarPath: json['avatar_url'] as String?,
    currencyCode: json['currency_code'] as String?,
    timezone: json['timezone'] as String?,
  );

  /// Columns read by [Profile.fromJson].
  static const String columns =
      'id, full_name, mobile, avatar_url, currency_code, timezone';

  final String id;
  final String? fullName;
  final String? mobile;
  final String? avatarPath;
  final String? currencyCode;
  final String? timezone;
}
