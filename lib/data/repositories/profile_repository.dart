import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's profile row. RLS limits every query to that row; the
/// id filter keeps queries explicit.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

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

  Future<Profile> updateProfile({
    required String fullName,
    required String? mobile,
  }) => guardSupabase(() async {
    final Map<String, dynamic> row = await _client
        .from('profiles')
        .update(<String, dynamic>{'full_name': fullName, 'mobile': mobile})
        .eq('id', _userId)
        .select(Profile.columns)
        .single();
    return Profile.fromJson(row);
  });
}
