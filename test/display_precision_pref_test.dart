import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/engine/presentation.dart';
import 'package:tallynote/ui/editor_pane.dart';
import 'package:tallynote/main.dart';

void main() {
  testWidgets('display precision pref reaches pane results', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tallynote.displayPrecision': '4',
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(TallynoteApp),
      findsOneWidget,
    );
    final p = tester.widget<EditorPane>(find.byType(EditorPane).first).pane;
    expect(p.displayPrecision, DisplayPrecision.d4);
  });
}
