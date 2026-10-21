import 'dart:async';
import 'dart:developer' as developer;

import 'package:finance_tracker/bindings/user_scope.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/datasources/local/saved_login_store.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/receipt_store.dart';
import 'package:finance_tracker/domain/entities/saved_login.dart';
import 'package:finance_tracker/features/notifications/notification_target.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Several accounts signed in on one device, and switching between them like
/// the account switcher of a social app.
///
/// The active account is the Supabase session; the others wait in
/// [SavedLoginStore] with their sessions. Each account has its own local
/// database file, so a switch is quick, works offline and never loses another
/// account's unsent changes. A switch:
/// 1. saves the active session (refreshed first when about to expire);
/// 2. replaces the app with the switching screen and removes the controllers
///    holding the account's data;
/// 3. with sync paused, makes the other session active and opens its file;
/// 4. loads that account's preferences, starts a sync and shows its home.
///
/// Notifications of every signed-in account keep arriving. Tapping one that
/// belongs to another signed-in account switches to it first, then opens it.
///
/// Together with AuthController this is where the app navigates on account
/// changes: AuthController hands sign-ins and sign-outs over to it.
class AccountSwitchController extends GetxController {
  AccountSwitchController({
    required this._auth,
    required this._store,
    required this._notifications,
    this._database,
    this._syncEngine,
    this._receipts,
  });

  final AuthRepository _auth;
  final SavedLoginStore _store;
  final NotificationCoordinator _notifications;
  final AppDatabase? _database;
  final SyncEngine? _syncEngine;
  final ReceiptStore? _receipts;

  /// Every account signed in on this device, most recently used first.
  final RxList<SavedLogin> logins = <SavedLogin>[].obs;

  /// The account being switched to, for the switching screen.
  final Rxn<SavedLogin> switchingTo = Rxn<SavedLogin>();

  /// The account the app is showing. Kept here because at a sign-out the
  /// session, and with it the user id, is already gone.
  String? _activeId;
  bool _busy = false;

  static const String limitMessage =
      'You can keep up to ${SavedLoginStore.maxLogins} accounts on this '
      'device. Sign out of one to add another.';

  String? get activeUserId => _auth.currentUserId;

  bool get isSwitching => _busy;

  bool get canAddAccount => logins.length < SavedLoginStore.maxLogins;

  /// The account that takes over when the active one signs out, if any.
  SavedLogin? get nextAfterSignOut {
    final List<SavedLogin> others = _others(activeUserId);
    return others.isEmpty ? null : others.first;
  }

  /// Whether a saved account can take over at start-up, when the app has no
  /// session (the last active one ended while the app was closed).
  bool get canResume => _others(null).isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    _notifications
      ..hasOtherAccounts = ((String userId) => _others(userId).isNotEmpty)
      ..onOtherAccountTarget = _openForOtherAccount;
    _activeId = _auth.currentUserId;
    _reload();
    // An install that signed in before accounts could be switched has its
    // account saved here from the first start on.
    if (_activeId != null) unawaited(_rememberActiveQuietly());
  }

  // ---------------------------------------------------------------------
  // Switching

  /// Switches to the saved account [userId]. [then] opens once that
  /// account's home is showing (a tapped notification of that account).
  Future<void> switchTo(
    String userId, {
    NotificationTarget? then,
    bool announce = false,
  }) async {
    if (_busy) return;
    if (userId == activeUserId) {
      if (then != null) _notifications.open(then);
      return;
    }
    final SavedLogin? login = _store.login(userId);
    final String? session = _store.sessionFor(userId);
    if (login == null || session == null) {
      _reload();
      AppSnackbar.show('That account is no longer signed in on this device.');
      return;
    }
    _busy = true;
    try {
      // Before anything changes: when the active session cannot be saved,
      // the user stays where they are.
      final AccountSession? current = await _auth.holdCurrentSession();
      if (current != null) await _rememberActive(current);
    } on AppException catch (error) {
      _busy = false;
      _auth.resumeAutoRefresh();
      AppSnackbar.show(error.message);
      return;
    }

    final bool switched = await _switch(
      login,
      session,
      then: then,
      announce: announce ? 'Switched to ${login.label}' : null,
    );
    if (!switched) {
      // The other session had ended; the previous account is still active.
      await _enterActive(
        announce:
            'You were signed out of ${login.email}. Sign in to it again to '
            'switch to it.',
      );
    }
  }

  /// Signs in to one more account and switches to it; the active account
  /// stays signed in. Throws [AppException] (wrong password, offline, limit).
  Future<void> addAccount({
    required String email,
    required String password,
  }) async {
    if (_busy) return;
    if (!canAddAccount) throw const AuthFailure(limitMessage);
    final AccountSession added = await _auth.signInDetached(
      email: email,
      password: password,
    );
    if (added.userId == activeUserId) {
      throw const AuthFailure('You are already using this account.');
    }
    final SavedLogin? known = _store.login(added.userId);
    await _store.save(
      SavedLogin(
        userId: added.userId,
        email: added.email,
        displayName: added.displayName ?? known?.displayName,
        avatarUrl: known?.avatarUrl,
        lastUsedAt: DateTime.now(),
      ),
      session: added.session,
    );
    _reload();
    await switchTo(added.userId);
  }

  /// Keeps the active account's name in the switcher current.
  void updateActiveName(String? fullName) =>
      updateActiveProfile(fullName: fullName);

  /// Keeps the active account's name and avatar in the switcher current.
  void updateActiveProfile({String? fullName, String? avatarUrl}) {
    final String? userId = activeUserId;
    if (userId == null) return;
    final SavedLogin? login = _store.login(userId);
    if (login == null) return;

    final String? name = fullName?.trim();
    final String? effectiveName = (name != null && name.isNotEmpty)
        ? name
        : login.displayName;
    final String? effectiveAvatar = avatarUrl ?? login.avatarUrl;

    if (login.displayName == effectiveName &&
        login.avatarUrl == effectiveAvatar) {
      return;
    }

    unawaited(
      _store
          .save(
            login.copyWith(
              displayName: effectiveName,
              avatarUrl: effectiveAvatar,
            ),
          )
          .then((_) => _reload())
          .catchError((Object error) => _logStorage(error)),
    );
  }

  // ---------------------------------------------------------------------
  // Sign-in and sign-out (from AuthController)

  /// A sign-in on the sign-in screen, or the active account confirming its
  /// password again (change password, delete account). A new account gets
  /// its own database file before anything reads or syncs.
  Future<void> handleSignedIn() async {
    final AccountSession? session = _auth.currentSession;
    if (session == null) return;
    if (session.userId != _activeId) {
      _activeId = session.userId;
      await _whilePaused(() async => _database?.openFor(session.userId));
      await _syncEngine?.resetStatus();
    }
    try {
      await _rememberActive(session);
    } on AppException catch (error) {
      _logStorage(error);
    }
  }

  /// The active account signed out, from the app or because its session
  /// ended. Its local data goes, as it always has at sign-out
  /// (docs/04_SECURITY_RLS.md). The most recently used other account takes
  /// over; with none, the sign-in screen shows.
  Future<void> handleSignedOut([String? userId]) async {
    final String? leaving = userId ?? _activeId ?? _auth.currentUserId;
    _activeId = null;
    if (leaving != null) await _forget(leaving, deleteData: false);
    await _takeOver(_others(leaving), discard: leaving);
  }

  /// Explicitly removes an account saved on this device and deletes its local database.
  Future<void> removeSavedAccount(String userId) async {
    if (userId == activeUserId) return;
    await _forget(userId, deleteData: true);
  }

  /// At start-up without a session: the most recently used saved account
  /// takes over (see [canResume]).
  Future<void> resumeSaved() => _takeOver(_others(null));

  // ---------------------------------------------------------------------

  /// Tries [candidates] in order until one becomes active. [discard] is the
  /// account that just signed out, whose database file is deleted once
  /// another file is open (or the signed-out one, when none takes over).
  Future<void> _takeOver(List<SavedLogin> candidates, {String? discard}) async {
    for (final SavedLogin login in candidates) {
      final String? session = _store.sessionFor(login.userId);
      if (session == null) continue;
      // A failed attempt changes no file, so [discard] is still to delete.
      if (await _switch(login, session, discard: discard)) return;
    }
    await _showSignIn(discard: discard, takeoverFailed: candidates.isNotEmpty);
  }

  /// Makes [login] the active account. Returns false, having forgotten the
  /// account, when its session has ended; the caller then decides where the
  /// app goes. [discard] is deleted after the new file is open.
  Future<bool> _switch(
    SavedLogin login,
    String session, {
    NotificationTarget? then,
    String? announce,
    String? discard,
  }) async {
    _busy = true;
    switchingTo.value = login;
    _notifications.beginAccountSwitch();
    await _showSwitchingScreen();
    try {
      final AccountSession active = await _whilePaused(() async {
        final AccountSession activated = await _auth.activateSession(session);
        await _database?.openFor(activated.userId);
        if (discard != null) await _removeLocalData(discard);
        return activated;
      });
      _activeId = active.userId;
      try {
        await _rememberActive(active, base: login);
      } on AppException catch (error) {
        _logStorage(error);
      }
      await _enterActive(then: then, announce: announce);
      return true;
    } on AuthFailure {
      await _forget(login.userId, deleteData: true);
      return false;
    } on Object catch (error) {
      // Not the session (a database or storage failure): carry on with
      // whichever account is active now.
      developer.log(
        'Account switch failed: ${error.runtimeType}',
        name: 'auth',
      );
      await _recover();
      return true;
    }
  }

  /// Shows the active account's home after a switch, or after a switch that
  /// could not happen.
  Future<void> _enterActive({
    NotificationTarget? then,
    String? announce,
  }) async {
    _auth.resumeAutoRefresh();
    _notifications.accountSwitched();
    if (then != null) _notifications.open(then);
    await _syncEngine?.resetStatus();
    loadUserScope();
    _reload();
    _busy = false;
    switchingTo.value = null;
    unawaited(Get.offAllNamed<void>(AppRoutes.dashboard));
    if (announce != null) AppSnackbar.show(announce);
  }

  /// After an unexpected failure mid-switch: open the file of whichever
  /// account is active, or show sign-in when none is.
  Future<void> _recover() async {
    final String? userId = _auth.currentUserId;
    if (userId == null) {
      await _showSignIn();
      return;
    }
    _activeId = userId;
    try {
      await _whilePaused(() async => _database?.openFor(userId));
    } on Object catch (error) {
      developer.log(
        'Database not reopened after a failed switch: ${error.runtimeType}',
        name: 'auth',
      );
    }
    await _enterActive(
      announce: 'The account could not be switched. Please try again.',
    );
  }

  /// No account is left: the sign-in screen shows, on the signed-out
  /// database, and the signed-out account's file is deleted.
  Future<void> _showSignIn({
    String? discard,
    bool takeoverFailed = false,
  }) async {
    unawaited(Get.offAllNamed<void>(AppRoutes.login));
    await _afterTransition();
    resetUserScope();
    if (takeoverFailed) await _notifications.allAccountsSignedOut();
    try {
      await _whilePaused(() async {
        await _database?.openFor(null);
        if (discard != null) await _removeLocalData(discard);
        // Data left in the signed-out file (the shared file of older
        // versions) belongs to nobody who is signed in.
        await _database?.clearAllUserData();
      });
      await _syncEngine?.resetStatus();
    } on Object catch (error) {
      // SyncEngine.claimLocalData still wipes before another account syncs.
      developer.log(
        'Local data was not cleared at sign-out: ${error.runtimeType}',
        name: 'auth',
      );
    }
    _busy = false;
    switchingTo.value = null;
    _reload();
  }

  Future<void> _showSwitchingScreen() async {
    unawaited(Get.offAllNamed<void>(AppRoutes.switchAccount));
    // Once this resumes the previous account's screens are gone, so no
    // screen still reads a controller being removed.
    await _afterTransition();
    resetUserScope();
  }

  void _openForOtherAccount(NotificationTarget target) {
    final String? owner = target.userId;
    if (owner == null) return;
    if (_store.sessionFor(owner) == null) {
      AppSnackbar.show(
        'That notification is for an account that is not signed in on this '
        'device.',
      );
      return;
    }
    unawaited(switchTo(owner, then: target, announce: true));
  }

  // ---------------------------------------------------------------------
  // Saved accounts

  /// Saves the active account with [session]. Throws [StorageFailure].
  Future<void> _rememberActive(
    AccountSession session, {
    SavedLogin? base,
  }) async {
    final SavedLogin? known = base ?? _store.login(session.userId);
    await _store.save(
      SavedLogin(
        userId: session.userId,
        email: session.email.isNotEmpty ? session.email : known?.email ?? '',
        displayName: known?.displayName ?? session.displayName,
        avatarUrl: known?.avatarUrl,
        lastUsedAt: DateTime.now(),
      ),
      session: session.session,
    );
    _reload();
  }

  Future<void> _rememberActiveQuietly() async {
    final AccountSession? session = _auth.currentSession;
    if (session == null) return;
    try {
      await _rememberActive(session);
    } on AppException catch (error) {
      _logStorage(error);
    }
  }

  /// Removes [userId] from the saved accounts and, when [deleteData], its
  /// database file (which must not be the open one).
  Future<void> _forget(String userId, {required bool deleteData}) async {
    try {
      await _store.remove(userId);
    } on AppException catch (error) {
      _logStorage(error);
    }
    if (deleteData) {
      try {
        await _removeLocalData(userId);
      } on Object catch (error) {
        developer.log(
          'Local data of a signed-out account not removed: '
          '${error.runtimeType}',
          name: 'auth',
        );
      }
    }
    _reload();
  }

  Future<void> _removeLocalData(String userId) async {
    await _database?.removeUser(userId);
    await _receipts?.deleteLocal(userId);
  }

  /// Saved accounts other than [userId] that can be switched to.
  List<SavedLogin> _others(String? userId) => _store
      .logins()
      .where(
        (SavedLogin login) =>
            login.userId != userId && _store.sessionFor(login.userId) != null,
      )
      .toList();

  void _reload() => logins.assignAll(_store.logins());

  Future<T> _whilePaused<T>(Future<T> Function() action) {
    final SyncEngine? engine = _syncEngine;
    return engine == null ? action() : engine.whilePaused(action);
  }

  static Future<void> _afterFrame() {
    final Completer<void> done = Completer<void>();
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => done.complete())
      ..scheduleFrame();
    return done.future;
  }

  /// Waits until the route just pushed with `offAllNamed` has finished its
  /// transition: until then the screens it replaces are still built and
  /// still read their controllers. Bounded, so a paused animation (app in
  /// the background) cannot hold a switch forever.
  static Future<void> _afterTransition() async {
    await _afterFrame();
    // The navigator's top route: Get.routing.route can point at a route
    // below while the replaced ones are being removed.
    Route<dynamic>? route;
    Get.key.currentState?.popUntil((Route<dynamic> top) {
      route = top;
      return true;
    });
    final Route<dynamic>? pushed = route;
    final Animation<double>? animation = pushed is ModalRoute<dynamic>
        ? pushed.animation
        : null;
    if (animation != null && !animation.isCompleted) {
      final Completer<void> done = Completer<void>();
      void onStatus(AnimationStatus status) {
        if (status.isCompleted && !done.isCompleted) done.complete();
      }

      animation.addStatusListener(onStatus);
      await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
      animation.removeStatusListener(onStatus);
    }
    // The replaced routes are disposed in the frame after the transition.
    await _afterFrame();
  }

  static void _logStorage(Object error) => developer.log(
    'Saved accounts not updated: ${error.runtimeType}',
    name: 'auth',
  );
}
