import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's user_settings row. RLS limits every query to that row;
/// the user_id filter keeps queries explicit.
class UserSettingsRepository {
  UserSettingsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw AuthFailure.sessionExpired;
    return id;
  }

  Future<UserSettings> fetch() => guardSupabase(() async {
    final Map<String, dynamic> row = await _client
        .from('user_settings')
        .select(UserSettings.columns)
        .eq('user_id', _userId)
        .single();
    return UserSettings.fromJson(row);
  });

  /// Writes all editable preference columns at once.
  Future<UserSettings> save(UserSettings settings) => guardSupabase(() async {
    final Map<String, dynamic> row = await _client
        .from('user_settings')
        .update(settings.toJson())
        .eq('user_id', _userId)
        .select(UserSettings.columns)
        .single();
    return UserSettings.fromJson(row);
  });
}
