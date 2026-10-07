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
