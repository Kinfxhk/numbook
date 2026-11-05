import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_pane.dart';
import 'package:tallynote/ui/editor_paper.dart';
import 'package:tallynote/ui/editor_view.dart';

void main() {
  testWidgets('paper prefs load into EditorView', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tallynote.paperStyle': 'single',
      'tallynote.highlightCurrentLine': true,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 400));

    final pane = tester.widget<EditorPane>(find.byType(EditorPane).first);
    expect(pane.pane.paperStyle, PaperStyle.single);
    expect(pane.pane.highlightCurrentLine, isTrue);

    final view = tester.widget<EditorView>(find.byType(EditorView).first);
    expect(view.paperStyle, PaperStyle.single);
    expect(view.highlightCurrentLine, isTrue);
  });

  testWidgets('settings paper choice updates pane and prefs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 400));

    if (find.byIcon(Icons.keyboard_double_arrow_left).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left).first);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byIcon(Icons.tune).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('paper-double')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tallynote.paperStyle'), 'double');

    final pane = tester.widget<EditorPane>(find.byType(EditorPane).first);
    expect(pane.pane.paperStyle, PaperStyle.double);
  });
}
