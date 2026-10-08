import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/core/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// flutter test draws text in a font whose letters are far wider than the real
// one, so a fixed card width in pixels would mean something different here
// than on a phone. These tests therefore measure the width the labels are
// given and set the card from that, so they hold with any font.

const String _income = 'Income this month';
const String _expense = 'Expense this month';

Future<void> _pumpCard(
  WidgetTester tester, {
  required double cardWidth,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: cardWidth,
            child: BalanceCard(
              currentBalance: Decimal.parse('39000'),
              openingBalance: Decimal.parse('10000'),
              monthIncome: Decimal.parse('30000'),
              monthExpense: Decimal.parse('1000'),
              isHidden: false,
              onToggleHidden: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

RenderParagraph _paragraph(WidgetTester tester, String label) =>
    tester.renderObject<RenderParagraph>(find.text(label));

/// The width the label is allowed to use.
double _labelWidth(WidgetTester tester, String label) =>
    _paragraph(tester, label).constraints.maxWidth;

Size _tileSize(WidgetTester tester, String label) => tester.getSize(
  // The nearest container around the label is the tile itself.
  find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
);

/// Pumps the card so the labels get [labelWidth] to work with. The two tiles
/// share the card, so the label's width grows with the card's at a fixed rate;
/// that rate and offset are measured from two pumps, not assumed.
Future<void> _pumpWithLabelWidth(
  WidgetTester tester,
  double labelWidth, {
  double textScale = 1,
}) async {
  await _pumpCard(tester, cardWidth: 800, textScale: textScale);
  final double wide = _labelWidth(tester, _income);
  await _pumpCard(tester, cardWidth: 700, textScale: textScale);
  final double narrower = _labelWidth(tester, _income);
  final double perPixel = (wide - narrower) / 100;
  await _pumpCard(
    tester,
    cardWidth: 800 + (labelWidth - wide) / perPixel,
    textScale: textScale,
  );
}

void main() {
  /// Height of a label that fits on one line, with plenty of room.
  Future<double> oneLine(WidgetTester tester, {double textScale = 1}) async {
    await _pumpCard(tester, cardWidth: 800, textScale: textScale);
    return tester.getSize(find.text(_expense)).height;
  }

  group('income and expense labels on the balance card', () {
    testWidgets('stay on one line when there is room', (
      WidgetTester tester,
    ) async {
      final double single = await oneLine(tester);

      for (final String label in <String>[_income, _expense]) {
        expect(tester.getSize(find.text(label)).height, single);
        expect(_paragraph(tester, label).didExceedMaxLines, isFalse);
      }
    });

    testWidgets('wrap onto a second line instead of being cut off', (
      WidgetTester tester,
    ) async {
      final double single = await oneLine(tester);
      // About two thirds of what the full label needs: too narrow for one
      // line, wide enough for each word group on its own line.
      final double full = _paragraph(tester, _expense).size.width;

      await _pumpWithLabelWidth(tester, full * 0.7);

      for (final String label in <String>[_income, _expense]) {
        final RenderParagraph paragraph = _paragraph(tester, label);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '"$label" must be shown in full, not cut to "mo…"',
        );
        expect(
          tester.getSize(find.text(label)).height,
          greaterThan(single * 1.5),
          reason: '"$label" is on two lines',
        );
      }
    });

    testWidgets(
      'the tiles keep the same height when only the longer label wraps',
      (WidgetTester tester) async {
        final double single = await oneLine(tester);
        final double expenseWidth = _paragraph(tester, _expense).size.width;
        final double incomeWidth = _paragraph(tester, _income).size.width;
        expect(
          expenseWidth,
          greaterThan(incomeWidth),
          reason: 'the case needs the expense label to be the longer one',
        );

        // Room for the income label on one line but not the expense label.
        await _pumpWithLabelWidth(tester, (expenseWidth + incomeWidth) / 2);

        expect(
          tester.getSize(find.text(_income)).height,
          single,
          reason: 'income still fits on one line',
        );
        expect(
          tester.getSize(find.text(_expense)).height,
          greaterThan(single * 1.5),
          reason: 'expense wraps',
        );
        expect(
          _tileSize(tester, _income).height,
          _tileSize(tester, _expense).height,
          reason: 'but the tiles are as tall as each other',
        );
      },
    );

    testWidgets('are not cut off with a larger system font', (
      WidgetTester tester,
    ) async {
      final double single = await oneLine(tester, textScale: 1.3);
      final double full = _paragraph(tester, _expense).size.width;

      await _pumpWithLabelWidth(tester, full * 0.7, textScale: 1.3);

      for (final String label in <String>[_income, _expense]) {
        expect(_paragraph(tester, label).didExceedMaxLines, isFalse);
        expect(tester.getSize(find.text(label)).height, greaterThan(single));
      }
      expect(tester.takeException(), isNull, reason: 'no overflow stripes');
    });

    testWidgets('still show both amounts', (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 340);

      expect(find.textContaining('30,000'), findsOneWidget);
      expect(find.textContaining('1,000.00'), findsWidgets);
    });
  });
}
