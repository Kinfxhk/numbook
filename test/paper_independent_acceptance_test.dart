import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_paper.dart';
import 'package:tallynote/ui/editor_view.dart';

Finder textEditor() => find.descendant(
  of: find.byType(EditorView),
  matching: find.byType(TextField),
);
EditorPaperPainter paper(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<EditorPaperPainter>()
    .single;

void main() {
  for (final factor in [1.0, 2.0]) {
    testWidgets(
      'independent actual editable geometry matches paper at textScale=$factor',
      (t) async {
        final text = 'gy 中文測試 ${'abcdef ' * 14}\n2+3\n';
        final c = TextEditingController(text: text);
        t.view.physicalSize = const Size(600, 500);
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(factor)),
                child: SizedBox(
                  width: 600,
                  height: 450,
                  child: EditorView(
                    controller: c,
                    results: const [],
                    dark: false,
                    answersVisible: false,
                    paperStyle: PaperStyle.single,
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final editable = t
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final p = paper(t);
        expect(
          p.layout.rowHeight,
          closeTo(editable.preferredLineHeight, 1),
          reason: 'row height from real RenderEditable, not hardcoded 28',
        );
        final cp = t.renderObject<RenderCustomPaint>(
          find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is EditorPaperPainter,
          ),
        );
        for (final offset in [0, text.indexOf('\n') + 1, text.length]) {
          final index = '\n'.allMatches(text.substring(0, offset)).length;
          final actual = editable.localToGlobal(
            editable.getLocalRectForCaret(TextPosition(offset: offset)).topLeft,
          );
          final measured = cp.localToGlobal(
            Offset(p.textLeft, p.layout.logicalLineTops[index]),
          );
          expect(
            actual.dy,
            closeTo(measured.dy, 1),
            reason: 'actual caret and paper share logical line $index',
          );
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 600));
        c.dispose();
        t.view.reset();
      },
    );
  }

  testWidgets(
    'independent paper fills viewport without changing plain scroll extent',
    (t) async {
      final c = TextEditingController(text: '1+1');
      t.view.physicalSize = const Size(600, 500);
      t.view.devicePixelRatio = 1;
      Widget shell(PaperStyle style) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 450,
            child: EditorView(
              controller: c,
              results: const [],
              dark: false,
              answersVisible: false,
              paperStyle: style,
            ),
          ),
        ),
      );
      await t.pumpWidget(shell(PaperStyle.plain));
      await t.pumpAndSettle();
      final scroll = t
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SingleChildScrollView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final oldMax = scroll.maxScrollExtent;
      await t.pumpWidget(shell(PaperStyle.double));
      await t.pumpAndSettle();
      final render = t.renderObject<RenderCustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is EditorPaperPainter,
        ),
      );
      // A painter can deliberately draw beyond its own layout size. Require its
      // effective drawable extent rather than assuming this is a normal widget.
      final bottom = paper(t).scrollOffset + paper(t).viewportHeight;
      expect(
        render.paintBounds.bottom,
        greaterThanOrEqualTo(bottom - 120),
        reason: 'short page background covers blank viewport',
      );
      expect(
        scroll.maxScrollExtent,
        oldMax,
        reason: 'appearance cannot add scroll range',
      );
      await t.pumpWidget(const SizedBox());
      c.dispose();
      t.view.reset();
    },
  );

  testWidgets(
    'independent style toggles preserve composing selection and focus',
    (t) async {
      final c = TextEditingController();
      final f = FocusNode();
      Widget shell(PaperStyle style) => MaterialApp(
        home: Scaffold(
          body: EditorView(
            controller: c,
            focusNode: f,
            results: const [],
            dark: false,
            paperStyle: style,
            highlightCurrentLine: true,
          ),
        ),
      );
      await t.pumpWidget(shell(PaperStyle.plain));
      await t.pumpAndSettle();
      f.requestFocus();
      await t.pump();
      const value = TextEditingValue(
        text: '中文 1+1',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      c.value = value;
      await t.pump();
      final before = t.state<EditableTextState>(find.byType(EditableText));
      for (final style in PaperStyle.values) {
        await t.pumpWidget(shell(style));
        await t.pump();
        expect(c.value, value);
        expect(f.hasFocus, isTrue);
        expect(
          identical(
            t.state<EditableTextState>(find.byType(EditableText)),
            before,
          ),
          isTrue,
        );
      }
      await t.pumpWidget(const SizedBox());
      c.dispose();
      f.dispose();
    },
  );

  testWidgets(
    'independent actual settings persist both preferences across restart',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'tallynote.locale': 'en',
        'tallynote.autoRates': false,
      });
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(const TallynoteApp());
      await t.pumpAndSettle();
      expect(
        t.widget<EditorView>(find.byType(EditorView).first).paperStyle,
        PaperStyle.plain,
      );
      expect(
        t
            .widget<EditorView>(find.byType(EditorView).first)
            .highlightCurrentLine,
        isFalse,
      );
      await t.tap(find.byIcon(Icons.settings_outlined).first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('paper-single')));
      await t.tap(find.byKey(const ValueKey('paper-single')));
      await t.pumpAndSettle();
      await t.ensureVisible(
        find.byKey(const ValueKey('switch-switch-current-line')),
      );
      await t.tap(find.byKey(const ValueKey('switch-switch-current-line')));
      await t.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tallynote.paperStyle'), 'single');
      expect(prefs.getBool('tallynote.highlightCurrentLine'), isTrue);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpWidget(const TallynoteApp());
      await t.pumpAndSettle();
      final view = t.widget<EditorView>(find.byType(EditorView).first);
      expect(view.paperStyle, PaperStyle.single);
      expect(view.highlightCurrentLine, isTrue);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 600));
      t.view.reset();
    },
  );

  testWidgets('scrolling does not remeasure the text layout', (t) async {
    final c = TextEditingController(
      text: List.generate(200, (i) => '$i + 1').join('\n'),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 450,
            child: EditorView(
              controller: c,
              results: const [],
              dark: false,
              paperStyle: PaperStyle.single,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final before = paper(t).layout;
    final scroll = t
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SingleChildScrollView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    scroll.jumpTo(280);
    await t.pump();
    expect(
      identical(paper(t).layout, before),
      isTrue,
      reason: 'scrolling must repaint only, not remeasure entire note',
    );
    expect(paper(t).scrollOffset, 280);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });

  test(
    'same height and row count but different logical wraps needs repaint',
    () {
      const style = TextStyle(
        fontFamily: 'monospace',
        fontSize: 15,
        height: 28 / 15,
      );
      final a = measureEditorTextLayout(
        text: '${'abc ' * 30}\nx',
        style: style,
        maxWidth: 240,
        scale: 1,
      );
      final b = measureEditorTextLayout(
        text: 'x\n${'abc ' * 30}',
        style: style,
        maxWidth: 240,
        scale: 1,
      );
      expect(a.contentHeight, b.contentHeight);
      expect(a.visualLines.length, b.visualLines.length);
      EditorPaperPainter p(EditorTextLayout l) => EditorPaperPainter(
        dark: false,
        paperStyle: PaperStyle.single,
        layout: l,
        highlightLogicalLine: 0,
        highlightEnabled: true,
        textLeft: 20,
        scrollOffset: 0,
        viewportHeight: 400,
      );
      expect(
        p(b).shouldRepaint(p(a)),
        isTrue,
        reason:
            'highlight span changes even if document height/count stays same',
      );
    },
  );

  testWidgets(
    'highlight has full wrapped row height and disappears without focus',
    (t) async {
      final c = TextEditingController(text: '${'gy 中文 ' * 16}\n2+3');
      final f = FocusNode();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: EditorView(
                controller: c,
                focusNode: f,
                results: const [],
                dark: false,
                answersVisible: false,
                highlightCurrentLine: true,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      f.requestFocus();
      c.selection = const TextSelection.collapsed(offset: 3);
      await t.pump();
      var p = paper(t);
      expect(p.highlightLogicalLine, 0);
      expect(p.layout.logicalLines[0].top, 0);
      expect(
        p.layout.logicalLines[0].bottom,
        closeTo(p.layout.logicalLineTops[1], 1),
        reason: 'highlight covers entire wrapped logical row, not only tight glyph box',
      );
      f.unfocus();
      await t.pump();
      await t.pump();
      expect(f.hasFocus, isFalse);
      expect(paper(t).highlightLogicalLine, isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      f.dispose();
    },
  );

  testWidgets(
    'independent restored split inherits paper preferences in both views',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'tallynote.locale': 'en',
        'tallynote.autoRates': false,
        'tallynote.paperStyle': 'double',
        'tallynote.highlightCurrentLine': true,
        'tallynote.split': true,
        'tallynote.splitPrimary': 'a',
        'tallynote.splitSheet': 'b',
        'tallynote.active.v1': 'a',
        'tallynote.sheets.v1': jsonEncode({
          'v': 2,
          'folders': [],
          'sheets': [
            for (final id in ['a', 'b'])
              {
                'id': id,
                'title': id,
                'content': '1+2',
                'updated': '2026-11-05T00:00:00.000',
              },
          ],
        }),
      });
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(const TallynoteApp());
      await t.pumpAndSettle();
      final views = t.widgetList<EditorView>(find.byType(EditorView)).toList();
      expect(views, hasLength(2));
      for (final view in views) {
        expect(view.paperStyle, PaperStyle.double);
        expect(view.highlightCurrentLine, isTrue);
      }
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 600));
      t.view.reset();
    },
  );
}
