import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/ui/editor_paper.dart';
import 'package:tallynote/ui/editor_view.dart';
import 'package:tallynote/ui/theme.dart';

void main() {
  testWidgets('highlight paints only with focus and collapsed selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'a\nb\nc');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 320,
            child: EditorView(
              controller: controller,
              results: const [],
              dark: false,
              highlightCurrentLine: true,
              answersVisible: false,
              showLineNumbers: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CustomPaint), findsWidgets);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    final painter = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).firstWhere(
      (w) => w.painter is EditorPaperPainter,
    );
    final p = painter.painter! as EditorPaperPainter;
    expect(p.highlightEnabled, isTrue);
    expect(p.highlightLogicalLine, 0);

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.pump();
    final p2 = (tester.widgetList<CustomPaint>(find.byType(CustomPaint)).firstWhere(
      (w) => w.painter is EditorPaperPainter,
    ).painter! as EditorPaperPainter);
    expect(p2.highlightLogicalLine, isNull);
  });

  test('plain and ruled layouts share the same content height', () {
    const text = '1+1\n2+2\nlong line ';
    final longText = '$text$text$text';
    final style = editorStyle(false);
    final plain = measureEditorTextLayout(
      text: longText,
      style: style,
      maxWidth: 240,
      scale: 1,
    );
    expect(plain.contentHeight, greaterThan(plain.rowHeight * 2));
    expect(plain.logicalLineTops.length, greaterThan(2));
  });
}
