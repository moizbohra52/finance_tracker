/// Screens of other apps that this app opens itself: the photo picker and
/// cropper, the file picker, the share sheet, system settings. The app lock
/// (AppLockController) does not ask again when the user comes straight back
/// from one of them.
abstract final class ExternalActivity {
  static int _open = 0;
  static DateTime? _startedAt;

  /// Settings and share intents complete as soon as the other screen is
  /// launched, before this app is hidden; a hide this soon after a launch
  /// still belongs to it.
  static const Duration _launchWindow = Duration(seconds: 3);

  /// Whether the app is (or is just about to be) behind a screen it opened.
  static bool get isActive {
    final DateTime? startedAt = _startedAt;
    return _open > 0 ||
        (startedAt != null &&
            DateTime.now().difference(startedAt) < _launchWindow);
  }

  /// Runs [action], which opens another app's screen.
  static Future<T> run<T>(Future<T> Function() action) async {
    _open++;
    _startedAt = DateTime.now();
    try {
      return await action();
    } finally {
      _open--;
    }
  }
}
