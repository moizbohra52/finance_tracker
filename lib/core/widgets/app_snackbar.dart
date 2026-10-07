import 'package:flutter/material.dart';

/// App-wide snackbars that survive navigation (e.g. "Account deleted" shown
/// while the app returns to the sign-in screen).
abstract final class AppSnackbar {
  /// Passed to GetMaterialApp.scaffoldMessengerKey.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static void show(String message) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}
