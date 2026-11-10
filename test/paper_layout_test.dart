import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/ui/editor_paper.dart';
import 'package:tallynote/ui/editor_view.dart';
import 'package:tallynote/ui/theme.dart';

void main() {
  test('measureEditorTextLayout matches legacy logical line tops', () {
    const scale = 1.0;
    const width = 200.0;
    const text = 'short\na much longer line that should wrap in the field';
    final style = editorStyle(false, scale: scale);
    final layout = measureEditorTextLayout(
      text: text,
      style: style,
      maxWidth: width,
      scale: scale,
    );
    expect(layout.logicalLineTops.length, 2);
    expect(layout.logicalLineTops.first, 0);
    expect(layout.visualLines.length, greaterThan(2));
    expect(layout.rowHeight, 28);
    expect(layout.logicalLines[1].height, greaterThan(layout.rowHeight));
  });

  testWidgets('EditorView line tops track measured layout for wrapped text', (
    tester,
  ) async {
    final text = '1+1\n${'0123456789' * 8}';
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.1)),
            child: SizedBox(
              width: 360,
              height: 480,
              child: EditorView(
                controller: controller,
                results: const [],
                dark: false,
                answersVisible: false,
                showLineNumbers: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(EditorView)) as dynamic;
    final tops = state.debugLogicalLineTops as List<double>;
    final maxW = state.debugTextMaxWidth as double;
    final field = tester.widget<TextField>(find.byType(TextField));
    final merged = DefaultTextStyle.of(tester.element(find.byType(TextField)))
        .style
        .merge(field.style!);
    final layout = measureEditorTextLayout(
      text: text,
      style: merged,
      maxWidth: maxW,
      scale: 1,
      textScaler: const TextScaler.linear(1.1),
    );
    expect(tops.length, layout.logicalLineTops.length);
    for (var i = 0; i < tops.length; i++) {
      expect(tops[i], closeTo(layout.logicalLineTops[i], 0.5));
    }
  });
}
