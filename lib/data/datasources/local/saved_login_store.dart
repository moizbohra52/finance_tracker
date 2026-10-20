import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/domain/entities/saved_login.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The accounts signed in on this device and their sessions, so the user can
/// switch between them without signing in again (AccountSwitchController).
///
/// A session is a secret. It is kept in the same app-private preferences file
/// in which supabase_flutter keeps the active session, so a saved account is
/// protected exactly like the signed-in one (docs/04_SECURITY_RLS.md). Sessions
/// are never logged and never leave this class except to be activated.
class SavedLoginStore {
  SavedLoginStore(this._preferences);

  static String get _key => 'auth.saved_logins_${AppEnv.current.name}';
  static const String _legacyKey = 'auth.saved_logins';

  /// Like social apps, a device keeps a handful of accounts: each one keeps
  /// its own local database and its own scheduled reminders.
  static const int maxLogins = 5;

  final SharedPreferences _preferences;
  List<_Entry>? _cache;

  /// Every saved account with a valid session in the current environment,
  /// most recently used first.
  List<SavedLogin> logins() => List<SavedLogin>.unmodifiable(
        _entries
            .where((_Entry e) => e.session != null && e.session!.isNotEmpty)
            .map((_Entry e) => e.login),
      );

  SavedLogin? login(String userId) {
    final _Entry? entry = _find(userId);
    if (entry == null || entry.session == null || entry.session!.isEmpty) {
      return null;
    }
    return entry.login;
  }

  /// The saved session of [userId], or null when there is none.
  String? sessionFor(String userId) {
    final _Entry? entry = _find(userId);
    final String? session = entry?.session;
    if (session == null || session.isEmpty) return null;
    return session;
  }

  /// Adds or updates [login]. A null [session] keeps the one already saved.
  /// Throws [StorageFailure] when it cannot be written.
  Future<void> save(SavedLogin login, {String? session}) async {
    final List<_Entry> next = List<_Entry>.of(_entries);
    final int index = next.indexWhere(
      (_Entry e) => e.login.userId == login.userId,
    );
    final _Entry entry = _Entry(
      login,
      session ?? (index >= 0 ? next[index].session : null),
    );
    if (index >= 0) {
      next[index] = entry;
    } else {
      next.add(entry);
    }
    await _write(next);
  }

  /// Forgets [userId] and its session. Throws [StorageFailure].
  Future<void> remove(String userId) async {
    final List<_Entry> next = _entries
        .where((_Entry e) => e.login.userId != userId)
        .toList();
    if (next.length == _entries.length) return;
    await _write(next);
  }

  _Entry? _find(String userId) {
    for (final _Entry entry in _entries) {
      if (entry.login.userId == userId) return entry;
    }
    return null;
  }

  List<_Entry> get _entries => _cache ??= _read();

  List<_Entry> _read() {
    try {
      String? raw = _preferences.getString(_key);
      if (raw == null || raw.isEmpty) {
        // Migrate legacy unscoped data if present and valid for this environment.
        final String? legacy = _preferences.getString(_legacyKey);
        if (legacy != null && legacy.isNotEmpty) {
          final Object? decodedLegacy = jsonDecode(legacy);
          if (decodedLegacy is List<Object?>) {
            final List<_Entry> valid = <_Entry>[];
            for (final Object? item in decodedLegacy) {
              if (_Entry.fromJson(item) case final _Entry entry) {
                if (entry.session != null &&
                    _isSessionForCurrentEnv(entry.session!)) {
                  valid.add(entry);
                }
              }
            }
            if (valid.isNotEmpty) {
              unawaited(
                _preferences.setString(
                  _key,
                  jsonEncode(<Map<String, Object?>>[
                    for (final _Entry entry in valid) entry.toJson(),
                  ]),
                ),
              );
            }
          }
          unawaited(_preferences.remove(_legacyKey));
          raw = _preferences.getString(_key);
        }
      }
      if (raw == null || raw.isEmpty) return <_Entry>[];
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return <_Entry>[];
      return _sorted(<_Entry>[
        for (final Object? item in decoded)
          if (_Entry.fromJson(item) case final _Entry entry)
            if (entry.session == null ||
                _isSessionForCurrentEnv(entry.session!))
              entry,
      ]);
    } on Object catch (error) {
      developer.log(
        'Saved accounts could not be read: ${error.runtimeType}',
        name: 'auth',
      );
      return <_Entry>[];
    }
  }

  /// Validates that a stored session token was issued for the active Supabase project.
  /// If [sessionString] is not a JSON object containing a Supabase JWT (e.g. mock test session),
  /// it is accepted as valid.
  static bool _isSessionForCurrentEnv(String sessionString) {
    try {
      final Object? decoded = jsonDecode(sessionString);
      if (decoded is! Map<String, dynamic>) return true;
      final Object? accessToken = decoded['access_token'];
      if (accessToken is! String || accessToken.isEmpty) {
        // Simple test sessions or non-JWT mocks are allowed
        return true;
      }
      final List<String> parts = accessToken.split('.');
      if (parts.length < 2) return true;
      final String normalized = base64Url.normalize(parts[1]);
      final String payloadJson = utf8.decode(base64Url.decode(normalized));
      final Object? payload = jsonDecode(payloadJson);
      if (payload is! Map<String, dynamic>) return true;
      final Object? iss = payload['iss'];
      if (iss is! String || iss.isEmpty) return true;
      final Uri? issUri = Uri.tryParse(iss);
      final Uri? envUri = Uri.tryParse(AppEnv.supabaseUrl);
      if (issUri != null && envUri != null && issUri.host.isNotEmpty) {
        return issUri.host.toLowerCase() == envUri.host.toLowerCase();
      }
      return true;
    } catch (_) {
      // Non-JSON strings (e.g. test dummy tokens) are treated as valid.
      return true;
    }
  }

  Future<void> _write(List<_Entry> entries) async {
    final List<_Entry> sorted = _sorted(entries);
    try {
      final bool saved = await _preferences.setString(
        _key,
        jsonEncode(<Map<String, Object?>>[
          for (final _Entry entry in sorted) entry.toJson(),
        ]),
      );
      if (!saved) throw const StorageFailure();
    } on StorageFailure {
      rethrow;
    } on Object {
      throw const StorageFailure();
    }
    _cache = sorted;
  }

  static List<_Entry> _sorted(List<_Entry> entries) => entries
    ..sort(
      (_Entry a, _Entry b) => b.login.lastUsedAt.compareTo(a.login.lastUsedAt),
    );
}

class _Entry {
  const _Entry(this.login, this.session);

  final SavedLogin login;
  final String? session;

  Map<String, Object?> toJson() => <String, Object?>{
    'user_id': login.userId,
    'email': login.email,
    'display_name': login.displayName,
    'avatar_url': login.avatarUrl,
    'last_used_at': login.lastUsedAt.toUtc().toIso8601String(),
    'session': session,
  };

  static _Entry? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final Object? userId = json['user_id'];
    final Object? email = json['email'];
    final Object? usedAt = json['last_used_at'];
    final Object? name = json['display_name'];
    final Object? avatarUrl = json['avatar_url'];
    final Object? session = json['session'];
    if (userId is! String || userId.isEmpty || email is! String) return null;
    return _Entry(
      SavedLogin(
        userId: userId,
        email: email,
        displayName: name is String ? name : null,
        avatarUrl: avatarUrl is String ? avatarUrl : null,
        lastUsedAt:
            (usedAt is String ? DateTime.tryParse(usedAt) : null) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      session is String && session.isNotEmpty ? session : null,
    );
  }
}
