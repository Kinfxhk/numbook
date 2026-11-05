import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/answer_column.dart';
import 'package:tallynote/ui/editor_view.dart';

void main() {
  testWidgets('EU format reaches answer alignment parsing', (tester) async {
    SharedPreferences.setMockInitialValues({'tallynote.numberFormat': 'eu'});
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 120));

    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '1,25\n1.234,56');
    await tester.pump(const Duration(milliseconds: 120));

    final parts = AnswerParts.parse('1,25', decimal: ',', group: '.');
    expect(parts.aligns, isTrue);
    expect(parts.fraction, '25');

    final big = AnswerParts.parse('1.234,56', decimal: ',', group: '.');
    expect(big.aligns, isTrue);
    expect(big.head, '1.234');
    expect(big.fraction, '56');
  });
}
