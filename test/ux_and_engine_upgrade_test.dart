import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/engine/values.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/answer_column.dart';
import 'package:tallynote/ui/editor_view.dart';
import 'package:tallynote/ui/marked_controller.dart';

double _euDecimalX(WidgetTester tester, String display) {
  final cell = find.byWidgetPredicate(
    (w) => w is AnswerReadout && w.display == display,
  );
  final comma = find.descendant(
    of: cell,
    matching: find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').startsWith(','),
    ),
  );
  if (comma.evaluate().isNotEmpty) return tester.getTopLeft(comma).dx;
  final head = find.descendant(of: cell, matching: find.byType(Text));
  return tester.getTopRight(head.first).dx;
}

void main() {
  group('engine upgrades', () {
    test('subtotal / 小計 sums since last subtotal without double-counting in sum or 合共', () {
      final engine = SheetEngine();
      final r = engine.evaluate([
        '# Trip',
        'flights 4000',
        'hotel 2000',
        'subtotal',
        'food 800',
        'rail 200',
        '小計',
        'sum',
        '合共',
      ]);

      expect(r[3].display, '6,000');
      expect(r[3].isSummary, isTrue);
      expect(r[6].display, '1,000');
      expect(r[6].isSummary, isTrue);
      expect(r[7].display, '7,000', reason: 'section sum ignores subtotals');
      expect(r[8].display, '7,000', reason: 'grand total ignores subtotals & sum');
      expect(r[8].isGrandTotal, isTrue);
    });

    test('user-declared subtotal variable still wins over built-in keyword', () {
      final engine = SheetEngine();
      final r = engine.evaluate(['100', 'subtotal = 42', 'subtotal + 8']);
      expect(r[1].display, '42');
      expect(r[2].display, '50');
    });

    test('Hong Kong 加一 (+10%) and Chinese 成 surcharges/discounts evaluate cleanly', () {
      final engine = SheetEngine();
      expect(engine.evaluate(['480 加一']).single.display, '528');
      expect(engine.evaluate(['加一 480']).single.display, '528');
      expect(engine.evaluate([r'HK$480 加一']).single.display, r'HK$528.00');
      expect(engine.evaluate(['100 加二成']).single.display, '120');
      expect(engine.evaluate(['100 減一成半']).single.display, '85');
    });

    test('¥ symbol honours JPY vs CNY setting', () {
      const rates = {'USD': 1.0, 'HKD': 7.8, 'JPY': 156.0, 'CNY': 7.2};
      final jpyEngine = SheetEngine(
        rates: rates,
        format: NumberFormat.ofPreset('us', yen: 'JPY'),
      );
      final cnyEngine = SheetEngine(
        rates: rates,
        format: NumberFormat.ofPreset('us', yen: 'CNY'),
      );

      expect(jpyEngine.evaluate(['¥100']).single.display, '¥100');
      expect(cnyEngine.evaluate(['¥100']).single.display, '¥100.00');
      expect(jpyEngine.evaluate(['¥156 in USD']).single.display, r'$1.00');
      expect(cnyEngine.evaluate(['¥7.2 in USD']).single.display, r'$1.00');
    });

    test('explain() covers conversions, retail discounts, and surcharges', () {
      final engine = SheetEngine(rates: const {'USD': 1, 'HKD': 7.8});
      final conv = engine.explain('100 USD in HKD');
      expect(conv, isNotEmpty);
      expect(conv.first, contains('1 USD = 7.8 HKD'));

      expect(engine.explain('打八折 480'), isNotEmpty);
      expect(engine.explain('480 加一'), isNotEmpty);
      expect(engine.explain('25% off 160'), isNotEmpty);
    });

    test('completionsFor returns scoped variables, labels, and #tags', () {
      final engine = SheetEngine();
      final results = engine.evaluate([
        'rent = 16000',
        '午餐 85 #food',
        're',
      ]);
      final vars = SheetEngine.completionsFor(results, 2, 're');
      expect(vars.map((e) => e.token), contains('rent'));
      expect(vars.firstWhere((e) => e.token == 'rent').preview, '16,000');

      final cjk = SheetEngine.completionsFor(results, 2, '午');
      expect(cjk.map((e) => e.token), contains('午餐'));

      final tags = SheetEngine.completionsFor(results, 2, '#fo');
      expect(tags.map((e) => e.token), contains('#food'));
    });
  });

  group('UI bug fixes & ergonomics', () {
    test('MarkedController preserves 1:1 plain text length across markers, headings, and tags', () {
      const sample =
          '# 每月預算\n**rent** = 16,000 #home\n{red}cards{/} -2,000\n// draft\nsubtotal';
      final c = MarkedController(text: sample, dark: false);
      addTearDown(c.dispose);
      final builder = Builder(
        builder: (ctx) {
          final span = c.buildTextSpan(
            context: ctx,
            style: const TextStyle(fontSize: 15),
            withComposing: false,
          );
          expect(span.toPlainText(), sample);
          expect(span.toPlainText().length, sample.length);
          return const SizedBox.shrink();
        },
      );
      expect(builder, isNotNull);
    });

    testWidgets('EU number format aligns comma decimals in live EditorPane', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'tallynote.numberFormat': 'eu'});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const TallynoteApp());
      await tester.pump(const Duration(milliseconds: 80));

      final editor = find.descendant(
        of: find.byType(EditorView),
        matching: find.byType(TextField),
      );
      await tester.enterText(editor, '1.234,56\n9,875+1\n500');
      await tester.pump(const Duration(milliseconds: 80));

      final x1 = _euDecimalX(tester, '1.234,56');
      final x2 = _euDecimalX(tester, '10,875');
      final x3 = _euDecimalX(tester, '500');
      expect(x1, closeTo(x2, 0.6));
      expect(x2, closeTo(x3, 0.6));
    });

    testWidgets('phone layout hides step chevron so long dates never overlap or cross divider', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const TallynoteApp());
      await tester.pump(const Duration(milliseconds: 80));

      // Mobile header shows the active sheet title
      expect(find.byKey(const ValueKey('header-sheet-title')), findsOneWidget);

      final editor = find.descendant(
        of: find.byType(EditorView),
        matching: find.byType(TextField),
      );
      await tester.enterText(editor, '2026-10-30 + 2 weeks\n(1+2)*3');
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.descendant(
          of: find.byType(EditorView),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsNothing,
        reason: 'tight mobile panes do not draw an overflowing step chevron',
      );

      final dividerHairline = tester
          .getCenter(
            find.descendant(
              of: find.byKey(const ValueKey('answer-divider')),
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.constraints?.maxWidth == 1,
              ),
            ),
          )
          .dx;
      final dateRect = tester.getRect(find.text('13 November 2026'));
      expect(
        dateRect.left,
        greaterThanOrEqualTo(dividerHairline - 1.0),
        reason: 'scaled date stays inside the answer column',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('inline autocomplete suggests variables and Tab completes them; selection shows live sum', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const TallynoteApp());
      await tester.pump(const Duration(milliseconds: 80));

      final editor = find.descendant(
        of: find.byType(EditorView),
        matching: find.byType(TextField),
      );
      await tester.tap(editor);
      await tester.enterText(editor, 'rent = 2500\nfood = 400\nre');
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byKey(const ValueKey('autocomplete-bar')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 80));

      final controller = tester.widget<TextField>(editor).controller!;
      expect(controller.text, 'rent = 2500\nfood = 400\nrent');

      // Multi-line selection reveals live selection sum in status bar
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.byKey(const ValueKey('status-selection-sum')),
        findsOneWidget,
      );
      expect(find.textContaining('5,400'), findsWidgets);
    });

    testWidgets('Ctrl+K opens the offline Command Palette and executes commands', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const TallynoteApp());
      await tester.pump(const Duration(milliseconds: 80));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('command-palette-input')),
        'Split view',
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('split-row')), findsOneWidget);
    });
  });
}
