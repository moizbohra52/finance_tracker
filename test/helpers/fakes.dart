import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/services/device_auth_service.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/data/datasources/local/saved_login_store.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/data/repositories/user_settings.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/features/app_lock/controllers/app_lock_controller.dart';
import 'package:finance_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_finance.dart';
import 'fake_notifications.dart';

/// Another account the fake server knows, for signing in to a second
/// account on the same device.
typedef FakeAccount = ({String userId, String password, String? name});

/// In-memory AuthRepository. Successful sign-in/out calls emit the same
/// status events Supabase would; [nextError] makes the next call fail.
///
/// The signed-in account is [userId] / [email]. Sessions handed out for
/// other accounts are JSON of the account, so activating one makes that
/// account current, as the real repository does; a session in [revoked]
/// has ended on the server.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this._signedIn = false});

  final StreamController<AuthStatus> _status =
      StreamController<AuthStatus>.broadcast();
  bool _signedIn;
  AppException? nextError;
  bool signUpStartsSession = true;

  String userId = 'user-1';
  String email = 'asha@example.com';

  /// Accounts [signInDetached] accepts, by email.
  final Map<String, FakeAccount> otherAccounts = <String, FakeAccount>{};

  /// User ids whose saved sessions no longer work.
  final Set<String> revoked = <String>{};
  int heldSessions = 0;

  @override
  Future<void> Function()? beforeSignOut;
  final List<String> calls = <String>[];

  void emit(AuthStatus status) {
    _signedIn = status != AuthStatus.signedOut;
    _status.add(status);
  }

  Future<void> _call(String name, [AuthStatus? onSuccess]) async {
    calls.add(name);
    final AppException? error = nextError;
    nextError = null;
    if (error != null) throw error;
    if (onSuccess != null) emit(onSuccess);
  }

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get currentEmail => _signedIn ? email : null;

  @override
  String? get currentUserId => _signedIn ? userId : null;

  static String sessionOf(String userId, String email) =>
      jsonEncode(<String, String>{'user_id': userId, 'email': email});

  @override
  AccountSession? get currentSession => _signedIn
      ? AccountSession(
          userId: userId,
          email: email,
          session: sessionOf(userId, email),
        )
      : null;

  @override
  Future<AccountSession> signInDetached({
    required String email,
    required String password,
  }) async {
    calls.add('signInDetached');
    final AppException? error = nextError;
    nextError = null;
    if (error != null) throw error;
    final FakeAccount? account = otherAccounts[email];
    if (account == null || account.password != password) {
      throw const AuthFailure('Incorrect email or password.');
    }
    return AccountSession(
      userId: account.userId,
      email: email,
      displayName: account.name,
      session: sessionOf(account.userId, email),
    );
  }

  @override
  Future<AccountSession?> holdCurrentSession() async {
    heldSessions++;
    return currentSession;
  }

  @override
  void resumeAutoRefresh() {}

  @override
  Future<AccountSession> activateSession(String session) async {
    calls.add('activateSession');
    final Map<String, dynamic> account =
        jsonDecode(session) as Map<String, dynamic>;
    final String id = account['user_id'] as String;
    if (revoked.contains(id)) throw AuthFailure.sessionExpired;
    // Like `initialSession`: no signed-in event.
    _signedIn = true;
    userId = id;
    email = account['email'] as String;
    return currentSession!;
  }

  @override
  Stream<AuthStatus> get statusChanges => _status.stream;

  @override
  Future<void> signIn({required String email, required String password}) =>
      _call('signIn', AuthStatus.signedIn);

  @override
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    await _call('signUp', signUpStartsSession ? AuthStatus.signedIn : null);
    return signUpStartsSession;
  }

  @override
  Future<void> sendPasswordReset(String email) => _call('sendPasswordReset');

  @override
  Future<void> updatePassword(String newPassword) => _call('updatePassword');

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _call('changePassword');

  @override
  Future<void> signOut() async {
    // Like the real repository, the pre-sign-out step runs first.
    await beforeSignOut?.call();
    await _call('signOut', AuthStatus.signedOut);
  }

  /// Like the real repository: the hook runs only after the password check
  /// succeeds, and before the account is removed.
  @override
  Future<void> deleteAccount({
    required String password,
    Future<void> Function()? beforeDelete,
  }) async {
    calls.add('deleteAccount');
    final AppException? error = nextError;
    nextError = null;
    if (error != null) throw error;
    await beforeDelete?.call();
    emit(AuthStatus.signedOut);
  }
}

/// The device's fingerprint / face check: every prompt is recorded and
/// answered with [next].
class FakeDeviceAuth implements DeviceAuthService {
  bool supported = true;

  /// Whether the device has biometrics or a screen lock set up.
  bool available = true;
  DeviceAuthResult next = DeviceAuthResult.success;
  final List<String> prompts = <String>[];

  @override
  bool get isSupportedPlatform => supported;

  @override
  Future<bool> isAvailable() async => supported && available;

  @override
  Future<DeviceAuthResult> authenticate(String reason) async {
    prompts.add(reason);
    return next;
  }
}

/// In-memory ProfileRepository. [nextError] fails the next call once;
/// [failUploads] fails every upload until cleared.
class FakeProfileRepository implements ProfileRepository {
  Profile profile = const Profile(
    id: 'user-1',
    fullName: 'Asha Rao',
    mobile: '+91 98765 43210',
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
  );
  AppException? nextError;
  bool failUploads = false;

  /// Fails profile updates only, so an upload can succeed and be orphaned.
  bool failUpdates = false;

  /// Fails photo links only, so the profile loads with the fallback picture.
  bool failLinks = false;

  /// Storage paths uploaded and removed, in order, for assertions.
  final List<String> uploads = <String>[];
  final List<String> removed = <String>[];
  int _uploadCount = 0;

  void _throwPending() {
    final AppException? error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Future<Profile> fetchProfile() async {
    _throwPending();
    return profile;
  }

  @override
  Future<Profile> updateProfile({
    String? fullName,
    String? mobile,
    bool clearMobile = false,
    String? currencyCode,
    String? timezone,
    String? avatarPath,
    bool clearAvatar = false,
  }) async {
    _throwPending();
    if (failUpdates) {
      throw const DatabaseFailure(
        "Couldn't load or save your data. Please try again.",
      );
    }
    return profile = Profile(
      id: profile.id,
      fullName: fullName ?? profile.fullName,
      mobile: clearMobile ? null : (mobile ?? profile.mobile),
      avatarPath: clearAvatar ? null : (avatarPath ?? profile.avatarPath),
      currencyCode: currencyCode ?? profile.currencyCode,
      timezone: timezone ?? profile.timezone,
    );
  }

  @override
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    _throwPending();
    if (failUploads) throw const DatabaseFailure("Couldn't update your photo.");
    final String path = 'user-1/${_uploadCount++}.$extension';
    uploads.add(path);
    return path;
  }

  @override
  Future<String> avatarLink(String path) async {
    _throwPending();
    if (failLinks) throw const NetworkFailure();
    return 'https://signed.example/$path?token=test';
  }

  @override
  Future<void> removeAvatar(String path) async {
    _throwPending();
    removed.add(path);
  }
}

/// In-memory UserSettingsRepository. Starts with the defaults a new account
/// has on the server.
class FakeUserSettingsRepository implements UserSettingsRepository {
  UserSettings settings = const UserSettings(
    dateFormat: 'd MMM y',
    numberFormat: 'indian',
    firstDayOfWeek: 'monday',
    languageCode: 'en',
    defaultAccountId: null,
  );
  AppException? nextError;

  /// Every row written, in order, so tests can see partial failures.
  final List<UserSettings> writes = <UserSettings>[];

  @override
  Future<UserSettings> fetch() async {
    final AppException? error = nextError;
    nextError = null;
    if (error != null) throw error;
    return settings;
  }

  @override
  Future<UserSettings> save(UserSettings next) async {
    final AppException? error = nextError;
    nextError = null;
    if (error != null) throw error;
    writes.add(next);
    return settings = next;
  }
}

/// Builds the app over fakes, then pumps it. A signed-in session loads the
/// preferences, as a real sign-in does.
Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  FakeProfileRepository? profile,
  FakeUserSettingsRepository? userSettings,
  ConnectivityService? connectivityService,
  FakeFinance? finance,
  FakeLocalNotifications? localNotifications,
  FakePush? push,
  NotificationsHandle? notifications,
  StorageService? storage,
  FakeDeviceAuth? deviceAuth,
  AppLockController? appLock,
}) async {
  await initializeDateFormatting(AppConstants.defaultLocale);
  await initializeDateFormatting(AppLanguage.hindi.dateLocale);
  // A restart passes the same storage, so the saved values must survive:
  // the mock is only reset for a fresh start.
  final StorageService preferences;
  if (storage != null) {
    preferences = storage;
  } else {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = StorageService(await SharedPreferences.getInstance());
  }
  final FakeFinance data = finance ?? FakeFinance();
  final NotificationsHandle handle =
      notifications ??
      await buildCoordinator(
        data,
        auth: auth,
        local: localNotifications,
        push: push,
        storage: preferences,
      );
  await handle.coordinator.initialize();
  // Like main(): initialised before the app, so it sees the back button
  // first. Detached afterwards, so it cannot act in the next test.
  final AppLockController lock =
      appLock ??
      AppLockController(
        deviceAuth: deviceAuth ?? FakeDeviceAuth(),
        storage: preferences,
        auth: auth,
      );
  lock.initialize();
  addTearDown(lock.detach);
  await tester.pumpWidget(
    FinanceTrackerApp(
      authRepository: auth,
      profileRepository: profile ?? FakeProfileRepository(),
      userSettingsRepository: userSettings ?? FakeUserSettingsRepository(),
      repositories: data.repositories,
      notificationCoordinator: handle.coordinator,
      appLock: lock,
      storageService: preferences,
      // The same preferences: supabase_flutter keeps its session there too.
      savedLogins: SavedLoginStore(await SharedPreferences.getInstance()),
      themeController: ThemeController(preferences),
      connectivityService:
          connectivityService ??
          ConnectivityService.forTest(
            watch: () => const Stream<NetworkStatus>.empty(),
            check: () async => NetworkStatus.unknown,
          ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view, taps it and waits for the UI to settle.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  Future<void> scrollIntoView() async {
    final Finder editableScrollables = find.descendant(
      of: find.byType(EditableText),
      matching: find.byType(Scrollable),
    );
    final Set<Element> excluded = editableScrollables.evaluate().toSet();
    final Finder pageScrollable = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Scrollable &&
          widget.axisDirection == AxisDirection.down,
    );
    final List<Element> candidates = pageScrollable
        .evaluate()
        .where((Element e) => !excluded.contains(e))
        .toList();
    if (candidates.isNotEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byElementPredicate((Element e) => e == candidates.last),
      );
    }
  }

  if (finder.evaluate().isEmpty) {
    await scrollIntoView();
  }
  try {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  } catch (_) {}

  if (finder.evaluate().isEmpty) {
    await scrollIntoView();
    await tester.pumpAndSettle();
  }

  await tester.tap(finder);
  await tester.pumpAndSettle();
}
