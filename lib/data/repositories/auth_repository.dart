import 'dart:async';
import 'dart:developer' as developer;

import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth transitions the app navigates on.
enum AuthStatus { signedIn, signedOut, passwordRecovery }

/// Supabase Auth access. Every method throws [AppException] on failure.
/// Sessions are persisted and refreshed by supabase_flutter itself.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  bool get isSignedIn => _auth.currentSession != null;

  String? get currentEmail => _auth.currentUser?.email;

  /// Replays transitions that happened before the first listener (e.g. a
  /// password-reset link that cold-started the app). Stream errors, such as an
  /// expired email link, arrive as [AppException].
  Stream<AuthStatus> get statusChanges => _auth.onAuthStateChange.transform(
    StreamTransformer<AuthState, AuthStatus>.fromHandlers(
      handleData: (AuthState state, EventSink<AuthStatus> sink) {
        final AuthStatus? status = switch (state.event) {
          AuthChangeEvent.signedIn => AuthStatus.signedIn,
          AuthChangeEvent.signedOut => AuthStatus.signedOut,
          AuthChangeEvent.passwordRecovery => AuthStatus.passwordRecovery,
          _ => null,
        };
        if (status != null) sink.add(status);
      },
      handleError:
          (Object error, StackTrace stackTrace, EventSink<AuthStatus> sink) =>
              sink.addError(mapSupabaseError(error), stackTrace),
    ),
  );

  Future<void> signIn({required String email, required String password}) =>
      guardSupabase(
        () => _auth.signInWithPassword(email: email, password: password),
      );

  /// Returns true when the user is signed in straight away, false when they
  /// must first open the confirmation link sent to [email]. [fullName] is read
  /// by the database signup trigger to fill profiles.full_name.
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await guardSupabase(
      () => _auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: AppConstants.authRedirectUrl,
        data: <String, dynamic>{'full_name': fullName},
      ),
    );
    return response.session != null;
  }

  /// Supabase answers the same way whether or not the email is registered,
  /// so this never reveals which emails have accounts.
  Future<void> sendPasswordReset(String email) => guardSupabase(
    () => _auth.resetPasswordForEmail(
      email,
      redirectTo: AppConstants.authRedirectUrl,
    ),
  );

  /// Sets a new password for the current (possibly recovery) session.
  Future<void> updatePassword(String newPassword) => guardSupabase(
    () => _auth.updateUser(UserAttributes(password: newPassword)),
  );

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _reauthenticate(currentPassword);
    await updatePassword(newPassword);
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on Exception catch (error) {
      // supabase_flutter clears the local session before calling the server,
      // so the device is signed out even when that call fails (e.g. offline).
      developer.log(
        'Server sign-out failed after local sign-out: ${error.runtimeType}',
        name: 'auth',
      );
    }
  }

  /// Permanently deletes the account and all its data, then signs out.
  /// The server only accepts this right after a password sign-in
  /// (see supabase/migrations/*_delete_my_account.sql).
  Future<void> deleteAccount({required String password}) async {
    await _reauthenticate(password);
    await guardSupabase(() => _client.rpc<void>('delete_my_account'));
    await signOut();
  }

  Future<void> _reauthenticate(String password) async {
    final String? email = currentEmail;
    if (email == null) throw AuthFailure.sessionExpired;
    try {
      await _auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      if (error.code == 'invalid_credentials') {
        throw const AuthFailure('Your password is incorrect.');
      }
      throw mapSupabaseError(error);
    } on Exception catch (error) {
      throw mapSupabaseError(error);
    }
  }
}
