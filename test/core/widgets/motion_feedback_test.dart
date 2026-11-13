import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);

/// Every haptic the app asks the phone for, by kind
/// ("HapticFeedbackType.lightImpact" and so on).
List<String> _recordHaptics(WidgetTester tester) {
  final List<String> haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return haptics;
}

void main() {
  group('CountUpMoney', () {
    testWidgets('counts up and ends on the exact amount', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(CountUpMoney(Decimal.parse('5750.35'))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('₹5,750.35'), findsNothing, reason: 'still counting');

      await tester.pumpAndSettle();
      expect(find.text('₹5,750.35'), findsOneWidget);
    });

    testWidgets('eases from the old amount to a new one', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(CountUpMoney(Decimal.parse('1000'))));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_host(CountUpMoney(Decimal.parse('750.50'))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('₹1,000.00'), findsNothing);
      expect(find.text('₹750.50'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('₹750.50'), findsOneWidget);
    });

    testWidgets('shows the amount at once when animations are off', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(CountUpMoney(Decimal.parse('42.10')), disableAnimations: true),
      );
      await tester.pump();
      expect(find.text('₹42.10'), findsOneWidget);
    });
  });

  group('haptics', () {
    testWidgets('confirming a delete gives a medium tap; cancelling none', (
      WidgetTester tester,
    ) async {
      final List<String> haptics = _recordHaptics(tester);
      late BuildContext context;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (BuildContext c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );

      unawaited(
        confirmDestructive(context, title: 'Delete?', message: 'Sure?'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(haptics, isEmpty);

      unawaited(
        confirmDestructive(context, title: 'Delete?', message: 'Sure?'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(haptics, <String>['HapticFeedbackType.mediumImpact']);
    });

    test(
      'a finished action calls the success hook; a failed one does not',
      () async {
        int successes = 0;
        SubmitState.onSuccess = () => successes++;
        addTearDown(() => SubmitState.onSuccess = null);

        final SubmitState state = SubmitState();
        expect(await state.run(() async {}), isTrue);
        expect(successes, 1);

        expect(
          await state.run(() async => throw const UnexpectedFailure()),
          isFalse,
        );
        expect(successes, 1);
      },
    );
  });
}
