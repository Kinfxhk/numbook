import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/data/document.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/engine/mcp_server.dart';
import 'package:tallynote/engine/values.dart';
import 'package:tallynote/io/document_io.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';
import 'package:tallynote/ui/marked_controller.dart';

void main() {
  group('Single-unknown linear solver & % change', () {
    final engine = SheetEngine(
      now: DateTime(2026, 10, 31, 9),
      rates: const {'USD': 1, 'HKD': 7.8},
    );

    test('solves dimensionless, percentage, currency, and unit equations', () {
      expect(engine.evaluate(['? * 30% = 1290']).single.display, '4,300');
      expect(engine.evaluate(['(? - 200) * 1.1 = 880']).single.display, '1,000');
      expect(engine.evaluate(['480 * ?% = 384']).single.display, '80%');
      expect(engine.evaluate(['300 + ?% = 345']).single.display, '15%');
      expect(engine.evaluate([r'$2500 + ? = $3200']).single.display, r'$700.00');
      expect(engine.evaluate([r'? * 30% = $1290']).single.display, r'$4,300.00');
      expect(engine.evaluate(['5 kg + ? = 8 kg']).single.display, '3 kg');
      expect(
        engine.evaluate(['rent = 2500', 'rent + ? = 4000']).last.display,
        '1,500',
      );
    });

    test('solves EU comma-decimal equations without locale drift', () {
      final eu = SheetEngine(format: NumberFormat.eu);
      expect(eu.evaluate(['? * 2 = 21,75']).single.display, '10,875');
    });

    test('refuses non-linear, singular, and multi-unknown equations', () {
      expect(engine.evaluate(['? * ? = 9']).single.display, isNull);
      expect(engine.evaluate(['? ^ 2 = 16']).single.display, isNull);
      expect(engine.evaluate(['100 / ? = 5']).single.display, isNull);
      expect(engine.evaluate(['0 * ? = 5']).single.display, isNull);
      expect(engine.evaluate(['? + ? = 10']).single.display, isNull);
    });

    test('explains solved equations and evaluates relative % change', () {
      expect(
        engine.explain('? * 30% = 1290'),
        ['? * 30% = 1290', '? = 4,300'],
      );
      expect(engine.evaluate(['from 80 to 100 in %']).single.display, '25%');
      expect(engine.evaluate(['change from 100 to 80']).single.display, '-20%');
      expect(engine.evaluate(['80 到 100 升跌']).single.display, '25%');
      expect(
        engine.evaluate([r'from $80 to $100 in %']).single.display,
        '25%',
      );
    });
  });

  group('Magnitude-aware ideal() compound units', () {
    final engine = SheetEngine(now: DateTime(2026, 10, 31, 9));

    test('picks human-scale imperial, metric, nautical, data, and time units', () {
      expect(engine.evaluate(['1 min * 1 mph']).single.display, '88 ft');
      expect(engine.evaluate(['3 min * 15 mph']).single.display, '0.75 mi');
      expect(engine.evaluate(['2000 s * 5 m/s']).single.display, '10 km');
      expect(engine.evaluate(['1 h * 10 knot']).single.display, '10 nmi');
      expect(engine.evaluate(['100 MB/s * 10 s']).single.display, '1 GB');
      expect(engine.evaluate(['500 MB / 50 MB/s']).single.display, '10 s');
    });
  });

  group('Formatted sheet exports & offline MCP server', () {
    test('DocumentIo preserves answers on lines with inline style markers', () {
      final engine = SheetEngine(now: DateTime(2026, 10, 31, 9));
      final sheets = [
        Sheet(
          id: 's1',
          title: 'Styled',
          content: '**rent** = 2500\n{green}bonus 500{/}\nsum',
        ),
      ];
      final md = DocumentIo.markdown(sheets, engine);
      expect(md, contains('**rent** = 2500  →  2,500'));
      expect(md, contains('bonus 500  →  500'));
      expect(md, contains('sum  →  3,000'));

      final csv = DocumentIo.csv(sheets, engine);
      expect(csv, contains('"Styled","1","rent = 2500","2,500",""'));
      expect(csv, contains('"Styled","3","sum","3,000",""'));

      final txt = DocumentIo.plainText(sheets, engine);
      expect(txt, contains('sum    3,000'));
    });

    test('McpServer handles initialize, tools/list, calc, eval_sheet, convert, and explain', () {
      final server = McpServer(fixedNow: DateTime(2026, 10, 31, 9));

      final init = server.handleMessage({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
      })!;
      expect((init['result'] as Map)['protocolVersion'], '2024-11-05');

      // Notifications return null
      expect(
        server.handleMessage({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
        isNull,
      );

      final listResp = server.handleMessage({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      })!;
      final tools = ((listResp['result'] as Map)['tools'] as List)
          .map((t) => (t as Map)['name'])
          .toList();
      expect(tools, containsAll(['calc', 'eval_sheet', 'convert', 'explain']));

      final calcResp = server.handleMessage({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'calc',
          'arguments': {'expression': '2h 30m + 45m'},
        },
      })!;
      final calcBody = jsonDecode(
        (((calcResp['result'] as Map)['content'] as List).single as Map)['text']
            as String,
      ) as Map<String, dynamic>;
      expect(calcBody['display'], '3 h 15 min');
      expect((calcBody['value'] as Map)['type'], 'duration');
      expect((calcBody['value'] as Map)['seconds'], 11700.0);

      final sheetResp = server.handleMessage({
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {
          'name': 'eval_sheet',
          'arguments': {
            'lines': ['**a** = 100', '200', 'subtotal'],
            'total': true,
            'dp': 2,
          },
        },
      })!;
      final sheetRows = (jsonDecode(
        (((sheetResp['result'] as Map)['content'] as List).single as Map)['text']
            as String,
      ) as Map)['lines'] as List;
      expect((sheetRows[2] as Map)['display'], '300.00');
      expect((sheetRows[3] as Map)['display'], '300.00');
    });
  });

  group('Scrubbable Numbers & ⌘⇧C quick Markdown copy', () {
    test('scrubNumberAt preserves decimals, grouping, EU format, and binary minus', () {
      // Plain integer
      expect(
        EditorView.scrubNumberAt('rent = 2500', 9, 5)?.$1,
        'rent = 2505',
      );
      // Grouped US number
      expect(
        EditorView.scrubNumberAt('1,250 * 2', 2, 10)?.$1,
        '1,260 * 2',
      );
      // Decimal places preserved (`12.50` steps by 0.01)
      expect(
        EditorView.scrubNumberAt('price = 12.50', 11, 25)?.$1,
        'price = 12.75',
      );
      // Binary subtraction (`100 - 20`): scrubbing `20` does not eat `-`
      expect(
        EditorView.scrubNumberAt('100 - 20', 7, 5)?.$1,
        '100 - 25',
      );
      // EU format (`1.250,50`)
      expect(
        EditorView.scrubNumberAt(
          '1.250,50 + 1',
          3,
          50,
          format: NumberFormat.eu,
        )?.$1,
        '1.251,00 + 1',
      );
    });

    testWidgets('Alt + horizontal drag scrubs number live in EditorView', (tester) async {
      final controller = MarkedController(text: '100 * 3', dark: false);
      final engine = SheetEngine();
      List<LineResult> results = engine.evaluate(['100 * 3']);
      controller.addListener(() {
        results = engine.evaluate(controller.text.split('\n'));
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  controller.addListener(() => setState(() {}));
                  return EditorView(
                    controller: controller,
                    results: results,
                    dark: false,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final fieldTopLeft = tester.getTopLeft(find.byType(TextField));
      final start = fieldTopLeft + const Offset(12, 14);
      final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(60, 0)); // +10 steps
      await tester.pump();
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();

      expect(controller.text, '110 * 3');
      expect(results.single.display, '330');
    });

    testWidgets('Cmd+Shift+C copies active sheet as Markdown', (tester) async {
      SharedPreferences.setMockInitialValues({});
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(const TallynoteApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '120 + 80');
      await tester.pump(const Duration(milliseconds: 500));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(copiedText, isNotNull);
      expect(copiedText, contains('120 + 80  →  200'));
    });
  });
}
