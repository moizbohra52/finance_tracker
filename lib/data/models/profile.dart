import 'package:flutter/foundation.dart';

/// The signed-in user's row in public.profiles (fields used so far).
@immutable
class Profile {
  const Profile({required this.id, this.fullName, this.mobile});

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    fullName: json['full_name'] as String?,
    mobile: json['mobile'] as String?,
  );

  /// Columns read by [Profile.fromJson].
  static const String columns = 'id, full_name, mobile';

  final String id;
  final String? fullName;
  final String? mobile;
}
