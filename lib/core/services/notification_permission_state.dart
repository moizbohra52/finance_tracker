/// Where notification permission stands, in the terms the UI acts on.
enum NotificationPermissionState {
  /// Not read from the OS yet.
  unknown,

  /// Notifications can be shown.
  granted,

  /// Not allowed, and the app has not asked yet or the OS may still show its
  /// prompt, so asking is worthwhile.
  denied,

  /// Not allowed after the app already asked. The OS will not prompt again
  /// (Android stops after repeated refusals, iOS after the first), so only
  /// the system settings can change it. Asking again would just annoy.
  blocked,

  /// This platform has no local notifications (web, desktop).
  unsupported;

  /// Combines what the OS reports with whether the app has already asked.
  static NotificationPermissionState resolve({
    required bool supported,
    required bool granted,
    required bool alreadyAsked,
  }) {
    if (!supported) return unsupported;
    if (granted) return NotificationPermissionState.granted;
    return alreadyAsked ? blocked : denied;
  }

  bool get isGranted => this == granted;

  /// The user can fix this by tapping "Allow" (system prompt).
  bool get canPrompt => this == denied;

  /// The user can fix this only in system settings.
  bool get needsSettings => this == blocked;
}
