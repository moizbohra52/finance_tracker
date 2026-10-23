import 'dart:async';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/models/profile.dart';
import 'package:finance_tracker/data/models/user_settings.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/data/repositories/user_settings.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:get/get.dart';

/// The signed-in user's formatting and default-account preferences.
///
/// One instance for the whole app, so every screen formats with the same
/// values. The values belong to the signed-in user: they load after sign-in and
/// are reset at sign-out, never deleted, so no other user sees them.
class SettingsController extends GetxController {
  SettingsController(
    this._profiles,
    this._userSettings,
    this._accounts,
    this._auth,
    this._notifier,
  );

  final ProfileRepository _profiles;
  final UserSettingsRepository _userSettings;
  final AccountRepository _accounts;
  final AuthRepository _auth;
  final DataChangeNotifier _notifier;

  final Rx<UserPreferences> preferences = UserPreferences.defaults.obs;

  /// Active accounts, for the default-account choice.
  final RxList<Account> accounts = <Account>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString loadError = RxnString();
  final SubmitState save = SubmitState();

  @override
  void onInit() {
    super.onInit();
    // Cold start with a saved session: the session is already restored, so
    // load now. A later sign-in loads through AuthController.
    if (_auth.isSignedIn) unawaited(load());
  }

  Future<void> load() async {
    isLoading.value = true;
    loadError.value = null;
    try {
      await _fetch();
    } on AppException catch (failure) {
      loadError.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// Saves [next]. Currency is written to the profile and the rest to
  /// user_settings. If a write fails, the screen reloads what the server holds,
  /// so it never shows a value that was not saved. Returns whether it saved.
  Future<bool> savePreferences(UserPreferences next) => save.run(() async {
    final UserPreferences previous = preferences.value;
    try {
      if (next.currencyCode != previous.currencyCode) {
        await _profiles.updateProfile(currencyCode: next.currencyCode);
      }
      await _userSettings.save(
        UserSettings(
          dateFormat: next.dateStyle.pattern,
          numberFormat: next.numberStyle.stored,
          firstDayOfWeek: next.weekStart.stored,
          languageCode: next.language.stored,
          defaultAccountId: next.defaultAccountId,
          upiId: next.upiId,
        ),
      );
    } on AppException {
      await _reloadQuietly();
      rethrow;
    }
    _apply(next);
    _notifier.markChanged();
  });

  /// Back to defaults. Called at sign-out, so the next user starts clean. An
  /// account switch keeps the language: the next account's own arrives with
  /// its settings, and the screens until then should not flash English.
  void reset({bool keepLanguage = false}) {
    _apply(
      keepLanguage
          ? UserPreferences.defaults.copyWith(
              language: preferences.value.language,
            )
          : UserPreferences.defaults,
    );
    accounts.clear();
    loadError.value = null;
    save.error.value = null;
    isLoading.value = true;
  }

  Future<void> _fetch() async {
    final (Profile profile, UserSettings settings) = await wait2(
      _profiles.fetchProfile(),
      _userSettings.fetch(),
    );
    final List<Account> all = await _accounts.getAccounts();
    accounts.assignAll(all.where((Account a) => a.isActive));
    _apply(_toPreferences(profile, settings));
  }

  /// A reload after a failed save. Its own failure is ignored: the save error
  /// is what the user needs to see.
  Future<void> _reloadQuietly() async {
    try {
      await _fetch();
    } on AppException {
      // Keep the values that were shown before the failed save.
    }
  }

  void _apply(UserPreferences next) {
    preferences.value = next;
    AppFormatters.preferences = next;
    // Before any change the locale is unset, which shows English.
    final Locale current = Get.locale ?? AppLanguage.english.locale;
    if (current != next.language.locale) {
      Get.locale = next.language.locale;
      // Rebuilds every open screen in the new language. Run between frames:
      // a reassemble requested during one fails.
      unawaited(Future<void>.delayed(Duration.zero, Get.forceAppUpdate));
    }
  }

  /// Stored strings that the app does not recognise fall back to the
  /// defaults, so a bad value never breaks a screen.
  static UserPreferences _toPreferences(
    Profile profile,
    UserSettings settings,
  ) => UserPreferences(
    currencyCode: profile.currencyCode ?? UserPreferences.defaults.currencyCode,
    dateStyle: DateStyle.fromStored(settings.dateFormat),
    numberStyle: NumberStyle.fromStored(settings.numberFormat),
    weekStart: WeekStart.fromStored(settings.firstDayOfWeek),
    language: AppLanguage.fromStored(settings.languageCode),
    defaultAccountId: settings.defaultAccountId,
    upiId: settings.upiId,
  );
}
