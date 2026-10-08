import 'dart:async';

import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/connectivity_service.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/core/theme/theme_controller.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/main.dart';
import 'fake_finance.dart';
import 'fake_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory AuthRepository. Successful sign-in/out calls emit the same
/// status events Supabase would; [nextError] makes the next call fail.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this._signedIn = false});

  final StreamController<AuthStatus> _status =
      StreamController<AuthStatus>.broadcast();
  bool _signedIn;
  AppException? nextError;
  bool signUpStartsSession = true;

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
  String? get currentEmail => _signedIn ? 'asha@example.com' : null;

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

  @override
  Future<void> deleteAccount({required String password}) =>
      _call('deleteAccount', AuthStatus.signedOut);
}

class FakeProfileRepository implements ProfileRepository {
  Profile profile = const Profile(
    id: 'user-1',
    fullName: 'Asha Rao',
    mobile: '+91 98765 43210',
  );
  AppException? nextError;

  @override
  Future<Profile> fetchProfile() async {
    _throwPending();
    return profile;
  }

  @override
  Future<Profile> updateProfile({
    required String fullName,
    required String? mobile,
  }) async {
    _throwPending();
    return profile = Profile(
      id: profile.id,
      fullName: fullName,
      mobile: mobile,
    );
  }

  void _throwPending() {
    final AppException? error = nextError;
    nextError = null;
    if (error != null) throw error;
  }
}

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  FakeProfileRepository? profile,
  ConnectivityService? connectivityService,
  FakeFinance? finance,
  FakeLocalNotifications? localNotifications,
  FakePush? push,
  NotificationsHandle? notifications,
}) async {
  await initializeDateFormatting(AppConstants.defaultLocale);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final StorageService storage = StorageService(
    await SharedPreferences.getInstance(),
  );
  final FakeFinance data = finance ?? FakeFinance();
  final NotificationsHandle handle =
      notifications ??
      await buildCoordinator(
        data,
        auth: auth,
        local: localNotifications,
        push: push,
        storage: storage,
      );
  await handle.coordinator.initialize();
  await tester.pumpWidget(
    FinanceTrackerApp(
      authRepository: auth,
      profileRepository: profile ?? FakeProfileRepository(),
      repositories: data.repositories,
      notificationCoordinator: handle.coordinator,
      storageService: storage,
      themeController: ThemeController(storage),
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
  if (finder.evaluate().isEmpty) {
    // Lazily built lists only create rows near the viewport.
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .byWidgetPredicate(
            (Widget widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
