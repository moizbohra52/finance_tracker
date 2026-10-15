import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/constants/app_env.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth transitions the app navigates on.
enum AuthStatus { signedIn, signedOut, passwordRecovery }

/// A signed-in session of one account, serialised so another account can be
/// active meanwhile. [session] is a secret: store it only in SavedLoginStore
/// and never log it.
class AccountSession {
  const AccountSession({
    required this.userId,
    required this.email,
    required this.session,
    this.displayName,
  });

  final String userId;
  final String email;

  /// The name given at sign-up, when there is one.
  final String? displayName;
  final String session;

  @override
  String toString() => 'AccountSession($userId)';
}

/// Supabase Auth access. Every method throws [AppException] on failure.
/// Sessions are persisted and refreshed by supabase_flutter itself.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// A session this close to expiry is refreshed before the app switches
  /// away from it, so the copy that is saved stays usable (see
  /// [holdCurrentSession]).
  static const Duration _refreshMargin = Duration(minutes: 5);

  /// Runs while the session is still valid, just before signing out (for
  /// example to stop push notifications to this device). A failure here never
  /// blocks sign-out.
  Future<void> Function()? beforeSignOut;

  bool get isSignedIn => _auth.currentSession != null;

  String? get currentEmail => _auth.currentUser?.email;

  String? get currentUserId => _auth.currentUser?.id;

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
      await beforeSignOut?.call();
    } on Object catch (error) {
      developer.log(
        'Pre sign-out step failed: ${error.runtimeType}',
        name: 'auth',
      );
    }
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
  ///
  /// [beforeDelete] runs once the password is confirmed and before the account
  /// is removed, for cleanup that must not happen for a wrong password (the
  /// profile photo). It must not throw.
  Future<void> deleteAccount({
    required String password,
    Future<void> Function()? beforeDelete,
  }) async {
    await _reauthenticate(password);
    await beforeDelete?.call();
    await guardSupabase(() => _client.rpc<void>('delete_my_account'));
    await signOut();
  }

  // ---------------------------------------------------------------------
  // Several accounts on one device

  /// The active session, or null when signed out.
  AccountSession? get currentSession => _toAccountSession(_auth.currentSession);

  /// Signs in to another account without touching the active one: a separate
  /// auth client does it and is thrown away. Returns the new session for the
  /// caller to keep.
  Future<AccountSession> signInDetached({
    required String email,
    required String password,
  }) async {
    final GoTrueClient detached = _detachedClient();
    try {
      final AuthResponse response = await guardSupabase(
        () => detached.signInWithPassword(email: email, password: password),
      );
      final AccountSession? session = _toAccountSession(response.session);
      // Email confirmation pending: there is no session to switch to.
      if (session == null) throw AuthFailure.sessionExpired;
      return session;
    } finally {
      detached.dispose();
    }
  }

  /// Returns the active session, refreshed first when it is about to expire,
  /// and stops automatic refreshes until [activateSession] or
  /// [resumeAutoRefresh]. Supabase refresh tokens are single-use, so the
  /// copy the caller saves must not be spent by a refresh while another
  /// account is active. Works offline: the session is then returned as is.
  Future<AccountSession?> holdCurrentSession() async {
    final Session? session = _auth.currentSession;
    final int? expiresAt = session?.expiresAt;
    if (session != null && expiresAt != null) {
      final DateTime expiry = DateTime.fromMillisecondsSinceEpoch(
        expiresAt * 1000,
      );
      if (expiry.difference(DateTime.now()) < _refreshMargin) {
        try {
          await _auth.refreshSession();
        } on Object catch (error) {
          developer.log(
            'Session not refreshed before switching: ${error.runtimeType}',
            name: 'auth',
          );
        }
      }
    }
    _auth.stopAutoRefresh();
    return currentSession;
  }

  void resumeAutoRefresh() => _auth.startAutoRefresh();

  /// Makes the saved [session] the active one, replacing the current session
  /// without signing it out, and returns it as it now is.
  ///
  /// An expired session is refreshed first on a separate client: refreshing
  /// a revoked one on the app's client would sign the current account out.
  /// A revoked session throws [AuthFailure.sessionExpired] and changes
  /// nothing. Offline, an expired session still becomes active (the app works
  /// from its local data) and supabase refreshes it once back online.
  Future<AccountSession> activateSession(String session) async {
    final Session? saved = _decodeSession(session);
    final String? refreshToken = saved?.refreshToken;
    if (saved == null || refreshToken == null) {
      throw AuthFailure.sessionExpired;
    }
    Session active = saved;
    if (saved.isExpired) {
      final GoTrueClient detached = _detachedClient();
      try {
        final AuthResponse response = await detached.setSession(refreshToken);
        active = response.session ?? saved;
      } on AuthRetryableFetchException {
        // Offline: keep the expired session; it refreshes when online.
      } on AuthException {
        throw AuthFailure.sessionExpired;
      } finally {
        detached.dispose();
      }
    }
    // Emits `initialSession`, which supabase_flutter persists and the app's
    // auth navigation ignores: the caller drives the switch itself.
    await _auth.setInitialSession(jsonEncode(active.toJson()));
    _auth.startAutoRefresh();
    return _toAccountSession(active)!;
  }

  static Session? _decodeSession(String session) {
    try {
      final Object? json = jsonDecode(session);
      return json is Map<String, dynamic> ? Session.fromJson(json) : null;
    } on Object {
      return null;
    }
  }

  GoTrueClient _detachedClient() => GoTrueClient(
    url: '${AppEnv.supabaseUrl}/auth/v1',
    headers: Map<String, String>.of(_auth.headers),
    autoRefreshToken: false,
    flowType: AuthFlowType.implicit,
  );

  static AccountSession? _toAccountSession(Session? session) {
    if (session == null) return null;
    final Object? name = session.user.userMetadata?['full_name'];
    return AccountSession(
      userId: session.user.id,
      email: session.user.email ?? '',
      displayName: name is String && name.trim().isNotEmpty ? name : null,
      session: jsonEncode(session.toJson()),
    );
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
