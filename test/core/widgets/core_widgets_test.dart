import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('AppButton', () {
    testWidgets('calls onPressed when tapped', (WidgetTester tester) async {
      int taps = 0;
      await _pump(tester, AppButton(label: 'Save', onPressed: () => taps++));

      await tester.tap(find.text('Save'));

      expect(taps, 1);
    });

    testWidgets('is disabled and shows a spinner while loading', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await _pump(
        tester,
        AppButton(label: 'Save', isLoading: true, onPressed: () => taps++),
      );

      await tester.tap(find.text('Save'));

      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('AppTextField', () {
    testWidgets('shows the validator error on submit', (
      WidgetTester tester,
    ) async {
      final GlobalKey<FormState> formKey = GlobalKey<FormState>();
      await _pump(
        tester,
        Form(
          key: formKey,
          child: AppTextField(
            label: 'Amount',
            validator: (String? value) =>
                (value == null || value.isEmpty) ? 'Enter an amount' : null,
          ),
        ),
      );

      expect(find.text('Enter an amount'), findsNothing);
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();

      expect(find.text('Enter an amount'), findsOneWidget);
    });

    testWidgets('password toggle reveals and hides the text', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const AppTextField(label: 'Password', obscureText: true),
      );
      bool isObscured() =>
          tester.widget<EditableText>(find.byType(EditableText)).obscureText;

      expect(isObscured(), isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(isObscured(), isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(isObscured(), isTrue);
    });
  });

  group('State views', () {
    testWidgets('LoadingState shows progress and message', (
      WidgetTester tester,
    ) async {
      await _pump(tester, const LoadingState(message: 'Loading accounts'));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading accounts'), findsOneWidget);
    });

    testWidgets('EmptyState renders and triggers its action', (
      WidgetTester tester,
    ) async {
      int actions = 0;
      await _pump(
        tester,
        EmptyState(
          icon: Icons.inbox_outlined,
          title: 'No transactions',
          message: 'Add your first transaction.',
          actionLabel: 'Add transaction',
          onAction: () => actions++,
        ),
      );

      expect(find.text('No transactions'), findsOneWidget);
      expect(find.text('Add your first transaction.'), findsOneWidget);
      await tester.tap(find.text('Add transaction'));
      expect(actions, 1);
    });

    testWidgets('ErrorState shows retry only when a handler is given', (
      WidgetTester tester,
    ) async {
      int retries = 0;
      await _pump(tester, const ErrorState(message: 'Could not load data.'));
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);

      await _pump(
        tester,
        ErrorState(message: 'Could not load data.', onRetry: () => retries++),
      );
      await tester.tap(find.text('Try again'));

      expect(retries, 1);
    });
  });
}
