import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Runs a Supabase call and converts any failure into an [AppException].
Future<T> guardSupabase<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on Exception catch (error) {
    throw mapSupabaseError(error);
  }
}

AppException mapSupabaseError(Object error) {
  if (error is AppException) return error;

  // Only the type and code are logged: messages can echo user input.
  developer.log(
    'Supabase call failed: ${error.runtimeType}'
    '${error is AuthException ? ' (${error.code})' : ''}'
    '${error is PostgrestException ? ' (${error.code})' : ''}',
    name: 'supabase',
  );

  if (error is AuthRetryableFetchException ||
      error is SocketException ||
      error is http.ClientException ||
      error is TimeoutException) {
    return const NetworkFailure();
  }
  if (error is StorageException) {
    return const DatabaseFailure(
      "Couldn't update your photo. Check your connection and try again.",
    );
  }
  if (error is AuthWeakPasswordException) {
    return const AuthFailure(
      'Choose a stronger password: at least 8 characters with letters and '
      'numbers.',
    );
  }
  if (error is AuthException) return AuthFailure(_authMessage(error.code));
  if (error is PostgrestException) {
    // 42501: denied by RLS or by delete_my_account's recent sign-in check.
    return error.code == '42501'
        ? const AuthFailure('Please sign in again to continue.')
        : const DatabaseFailure();
  }
  return const UnexpectedFailure();
}

String _authMessage(String? code) => switch (code) {
  'invalid_credentials' => 'Incorrect email or password.',
  'email_not_confirmed' =>
    'Confirm your email first. Check your inbox for the link.',
  'user_already_exists' || 'email_exists' =>
    'An account with this email already exists. Try signing in.',
  'same_password' => 'Your new password must be different from the old one.',
  'weak_password' =>
    'Choose a stronger password: at least 8 characters with letters and '
        'numbers.',
  'over_email_send_rate_limit' || 'over_request_rate_limit' =>
    'Too many attempts. Wait a minute and try again.',
  'session_not_found' ||
  'session_expired' ||
  'refresh_token_not_found' => AuthFailure.sessionExpired.message,
  'otp_expired' ||
  'flow_state_expired' ||
  'flow_state_not_found' ||
  'bad_code_verifier' =>
    'This link is invalid or has expired. Request a new one.',
  'signup_disabled' => 'New sign-ups are currently disabled.',
  _ => const UnexpectedFailure().message,
};
