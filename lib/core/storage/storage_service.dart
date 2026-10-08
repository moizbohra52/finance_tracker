import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists non-sensitive application preferences only. Financial data belongs
/// in the local database, not SharedPreferences.
class StorageService {
  StorageService(this._preferences);

  static const String _themeModeKey = 'appearance.theme_mode';
  static const String _accentColorKey = 'appearance.accent_color';

  final SharedPreferences _preferences;

  String? readThemeMode() => _read(_themeModeKey);

  String? readAccentColor() => _read(_accentColorKey);

  Future<void> saveThemeMode(String value) => _write(_themeModeKey, value);

  Future<void> saveAccentColor(String value) => _write(_accentColorKey, value);

  /// Generic keyed access for preferences owned by other features (for
  /// example notification settings). Same failure rules as the typed methods.
  String? readString(String key) => _read(key);

  Future<void> saveString(String key, String value) => _write(key, value);

  bool? readBool(String key) {
    try {
      return _preferences.getBool(key);
    } on Object {
      return null;
    }
  }

  Future<void> saveBool(String key, {required bool value}) async {
    try {
      if (!await _preferences.setBool(key, value)) throw const StorageFailure();
    } on StorageFailure {
      rethrow;
    } on Object {
      throw const StorageFailure();
    }
  }

  String? _read(String key) {
    try {
      return _preferences.getString(key);
    } on Object {
      // Preferences are optional; callers use their documented defaults.
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      if (!await _preferences.setString(key, value)) {
        throw const StorageFailure();
      }
    } on StorageFailure {
      rethrow;
    } on Object {
      throw const StorageFailure();
    }
  }
}
