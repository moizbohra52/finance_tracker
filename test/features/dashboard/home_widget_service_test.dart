import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/storage/storage_service.dart';
import 'package:finance_tracker/features/app_lock/controllers/app_lock_controller.dart';
import 'package:finance_tracker/features/dashboard/services/home_widget_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(
    'com.finance.tracker/home_widget',
  );
  final List<Object?> sent = <Object?>[];
  final DateTime november = DateTime(2026, 11, 16);
  late AppLockController lock;
  late HomeWidgetService widget;

  setUpAll(() => initializeDateFormatting(AppConstants.defaultLocale));

  setUp(() async {
    sent.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          sent.add(call.arguments);
          return null;
        });
    SharedPreferences.setMockInitialValues(<String, Object>{});
    lock = AppLockController(
      deviceAuth: FakeDeviceAuth(),
      storage: StorageService(await SharedPreferences.getInstance()),
      auth: FakeAuthRepository(signedIn: true),
    );
    widget = Get.put(HomeWidgetService(lock));
  });
  tearDown(Get.reset);

  void showFigures() => widget.show(
    balance: Decimal.parse('1500'),
    monthExpense: Decimal.parse('320'),
    month: november,
  );

  test('sends the figures and the month while App lock is off', () async {
    showFigures();
    await pumpEventQueue();

    final Map<Object?, Object?> values = sent.single! as Map<Object?, Object?>;
    expect(values['balance'], contains('1,500'));
    expect(values['expense'], contains('320'));
    expect(values['expenseLabel'], contains('November'));
    expect(values['note'], '');
  });

  test('turning App lock on resends only masks', () async {
    showFigures();
    lock.enabled.value = true;
    await pumpEventQueue();

    final Map<Object?, Object?> values = sent.last! as Map<Object?, Object?>;
    expect(values['balance'], '••••••');
    expect(values['expense'], '••••');
    expect(values['note'], isNotEmpty);
    expect(values.values.join(), isNot(contains('1,500')));
  });

  test('clear leaves the widget nothing to show', () async {
    showFigures();
    widget.clear();
    await pumpEventQueue();

    expect(sent.last, isNull);
  });
}
