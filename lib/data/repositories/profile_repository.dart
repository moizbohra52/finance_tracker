import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's profile row and avatar object. RLS limits every query
/// to that row and to the user's own avatar folder; the filters keep queries
/// explicit.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  static const String avatarBucket = 'avatars';

  /// How long a shown avatar link stays valid. A link that expires shows the
  /// fallback picture, and reopening the profile issues a fresh one.
  static const Duration avatarLinkLifetime = Duration(hours: 1);

  String get _userId {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw AuthFailure.sessionExpired;
    return id;
  }

  Future<Profile> fetchProfile() => guardSupabase(() async {
    final Map<String, dynamic> row = await _client
        .from('profiles')
        .select(Profile.columns)
        .eq('id', _userId)
        .single();
    return Profile.fromJson(row);
  });

  /// Only the fields that are passed change. [clearMobile] and [clearAvatar]
  /// remove a value, since null alone means "leave it as it is".
  Future<Profile> updateProfile({
    String? fullName,
    String? mobile,
    bool clearMobile = false,
    String? currencyCode,
    String? timezone,
    String? avatarPath,
    bool clearAvatar = false,
  }) => guardSupabase(() async {
    final Map<String, dynamic> updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (clearMobile) {
      updates['mobile'] = null;
    } else if (mobile != null) {
      updates['mobile'] = mobile;
    }
    if (currencyCode != null) updates['currency_code'] = currencyCode;
    if (timezone != null) updates['timezone'] = timezone;
    if (clearAvatar) {
      updates['avatar_url'] = null;
    } else if (avatarPath != null) {
      updates['avatar_url'] = avatarPath;
    }
    if (updates.isEmpty) return await fetchProfile();
    final Map<String, dynamic> row = await _client
        .from('profiles')
        .update(updates)
        .eq('id', _userId)
        .select(Profile.columns)
        .single();
    return Profile.fromJson(row);
  });

  /// Stores [bytes] under the user's folder and returns the object path. The
  /// name is unique per upload, so a new photo never overwrites the old one
  /// before the profile points at the new one.
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) => guardSupabase(() async {
    final String path =
        '$_userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage
        .from(avatarBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return path;
  });

  Future<String> avatarLink(String path) => guardSupabase(
    () => _client.storage
        .from(avatarBucket)
        .createSignedUrl(path, avatarLinkLifetime.inSeconds),
  );

  Future<void> removeAvatar(String path) => guardSupabase(
    () => _client.storage.from(avatarBucket).remove(<String>[path]),
  );
}
