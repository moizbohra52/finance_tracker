/// Failures surfaced to the presentation layer. [message] is always safe and
/// friendly enough to show to the user as-is; low-level errors are mapped to
/// these at the repository boundary (see supabase_error_mapper.dart).
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class AuthFailure extends AppException {
  const AuthFailure(super.message);

  static const AuthFailure sessionExpired = AuthFailure(
    'Your session has expired. Please sign in again.',
  );
}

final class NetworkFailure extends AppException {
  const NetworkFailure([
    super.message =
        "Can't reach the server. Check your connection and try again.",
  ]);
}

final class DatabaseFailure extends AppException {
  const DatabaseFailure([
    super.message = "Couldn't load or save your data. Please try again.",
  ]);
}

final class StorageFailure extends AppException {
  const StorageFailure([
    super.message = 'Your preferences could not be saved. Please try again.',
  ]);
}

final class UnexpectedFailure extends AppException {
  const UnexpectedFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// A message safe to show the user for any thrown [error].
String userMessage(Object error) =>
    error is AppException ? error.message : const UnexpectedFailure().message;
