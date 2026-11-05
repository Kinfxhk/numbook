import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/ui/editor_paper.dart';
import 'package:tallynote/ui/editor_view.dart';

void main() {
  testWidgets('paper background does not absorb taps', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: EditorView(
              controller: controller,
              results: const [],
              dark: false,
              paperStyle: PaperStyle.single,
              answersVisible: false,
              showLineNumbers: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IgnorePointer), findsWidgets);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(controller.selection.isValid, isTrue);
  });
}
