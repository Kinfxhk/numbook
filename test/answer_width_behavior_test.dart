import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';

import 'answer_divider_touch_test.dart' show boot, divider, editor, pane, withAnswer, done;

void main() {
  testWidgets('answer column can shrink below a long answer width', (
    tester,
  ) async {
    await boot(
      tester,
      const Size(1280, 800),
      prefs: {
        'tallynote.answerWidth': 320.0,
        'tallynote.answerWidthSet': true,
      },
    );
    await withAnswer(tester);
    await tester.enterText(editor(), '123456789*987654321');
    await tester.pump(const Duration(milliseconds: 400));
    final before = pane(tester).answerW;

    final band = tester.getRect(divider());
    final g = await tester.startGesture(band.center);
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(pane(tester).answerW, lessThan(before - 40));
    await g.up();
    await done(tester);
  });

  testWidgets('reset answer width returns to default', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tallynote.answerWidth': 400.0,
      'tallynote.answerWidthSet': true,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 400));

    pane(tester).resetAnswerWidth();
    await tester.pump();
    expect(pane(tester).answerW, 212);
    expect(pane(tester).explicitW, isFalse);
  });
}
