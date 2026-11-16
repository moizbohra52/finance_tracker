import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/features/app_lock/controllers/app_lock_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Feeds the Android home-screen widget (BalanceWidget.kt) the current
/// balance and this month's expense, as HomeController worked them out. With
/// App lock on it sends only masks, so the figures never reach the home
/// screen.
class HomeWidgetService extends GetxService {
  HomeWidgetService(this._appLock);

  final AppLockController _appLock;

  static const MethodChannel _channel = MethodChannel(
    'com.finance.tracker/home_widget',
  );

  ({Decimal balance, Decimal expense, DateTime month})? _last;
  Worker? _lockChanges;

  @override
  void onInit() {
    super.onInit();
    _lockChanges = ever<bool>(_appLock.enabled, (_) => _push());
  }

  @override
  void onClose() {
    _lockChanges?.dispose();
    super.onClose();
  }

  /// [month] names the month [monthExpense] is for, so a widget the app has
  /// not refreshed since the month turned says which month it shows.
  void show({
    required Decimal balance,
    required Decimal monthExpense,
    required DateTime month,
  }) {
    _last = (balance: balance, expense: monthExpense, month: month);
    _push();
  }

  /// Signed out or switched away: the widget asks to open the app instead.
  void clear() {
    _last = null;
    _push();
  }

  Future<void> _push() async {
    // shortcut: Android only; an iOS widget needs a WidgetKit target, which
    // can only be built on a Mac.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final ({Decimal balance, Decimal expense, DateTime month})? last = _last;
    final bool hidden = _appLock.enabled.value;
    try {
      await _channel.invokeMethod<void>(
        'update',
        last == null
            ? null
            : <String, String>{
                'balanceLabel': 'Current balance'.tr,
                'balance': hidden
                    ? '••••••'
                    : AppFormatters.money(last.balance),
                'expenseLabel': '@month expense'.trParams(<String, String>{
                  'month': AppFormatters.date(last.month, pattern: 'MMMM'),
                }),
                'expense': hidden ? '••••' : AppFormatters.money(last.expense),
                'note': hidden ? 'Tap to open'.tr : '',
              },
      );
    } on MissingPluginException {
      // Tests, and any engine without MainActivity's channel.
    } on PlatformException catch (error) {
      developer.log('Not updated: ${error.code}', name: 'home_widget');
    }
  }
}
