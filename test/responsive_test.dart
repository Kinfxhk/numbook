import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/answer_column.dart';
import 'package:tallynote/ui/editor_pane.dart';
import 'package:tallynote/ui/editor_view.dart';

/// The three form factors the split has to work on, plus the two phone widths
/// people actually hold: iPhone 14 and a 360px Android.
const phone = Size(390, 844);
const android = Size(360, 780);
const tabletPortrait = Size(820, 1180);
const tabletLandscape = Size(1180, 820);
const desktop = Size(1440, 900);

Map<String, Object> twoSheets() => {
  'tallynote.sheets.v1': jsonEncode({
    'v': 2,
    'folders': [],
    'sheets': [
      {
        'id': 'a',
        'title': 'Alpha',
        'content': '',
        'pinned': false,
        'customTitle': true,
        'updated': '2026-01-02T00:00:00.000',
      },
      {
        'id': 'b',
        'title': 'Beta',
        'content': 'seed',
        'pinned': false,
        'customTitle': true,
        'updated': '2026-01-01T00:00:00.000',
      },
    ],
  }),
  'tallynote.active.v1': 'a',
};

Finder paneAt(int i) => find.byType(EditorPane).at(i);

Finder fieldAt(int i) =>
    find.descendant(of: paneAt(i), matching: find.byType(TextField));

Finder answerAt(int i, String display) => find.descendant(
  of: paneAt(i),
  matching: find.byWidgetPredicate(
    (w) => w is AnswerReadout && w.display == display,
  ),
);

Future<void> boot(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues(twoSheets());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const TallynoteApp());
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
}

Future<void> toggle(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.vertical_split));
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  testWidgets('390 stacks; 820 and 1440 sit side by side', (tester) async {
    await boot(tester, phone);
    await toggle(tester);
    expect(find.byKey(const ValueKey('split-column')), findsOneWidget);
    expect(find.byKey(const ValueKey('split-row')), findsNothing);
    expect(find.byType(EditorPane), findsNWidgets(2));

    // 820 with the sidebar open leaves 569px of editor: two panes of 284 are
    // under the 340 a pane needs, so the guard stacks them
    tester.view.physicalSize = tabletPortrait;
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('split-column')), findsOneWidget);

    // the same 820 with the sidebar collapsed: each pane gets 409
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('split-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('split-column')), findsNothing);

    for (final size in [tabletLandscape, desktop]) {
      tester.view.physicalSize = size;
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byKey(const ValueKey('split-row')),
        findsOneWidget,
        reason: 'side by side at $size',
      );
      expect(find.byKey(const ValueKey('split-column')), findsNothing);
    }

    // and back down to a phone: the row folds into a column again
    tester.view.physicalSize = phone;
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('split-column')), findsOneWidget);
    // the toggle is still in the header at every size
    expect(find.byIcon(Icons.vertical_split), findsOneWidget);
  });

  for (final size in [phone, android, tabletPortrait, tabletLandscape, desktop]) {
    testWidgets('both panes add up at $size', (tester) async {
      await boot(tester, size);
      await toggle(tester);
      expect(find.byType(EditorPane), findsNWidgets(2));

      await tester.enterText(fieldAt(0), 'rent = 2500');
      await tester.pump(const Duration(milliseconds: 60));
      await tester.enterText(fieldAt(1), '200*12');
      await tester.pump(const Duration(milliseconds: 600));

      expect(answerAt(0, '2,500'), findsOneWidget, reason: 'left pane');
      expect(answerAt(1, '2,400'), findsOneWidget, reason: 'right pane');
      expect(answerAt(0, '2,400'), findsNothing, reason: 'no leak');
      expect(answerAt(1, '2,500'), findsNothing, reason: 'no leak');
    });
  }

  test('a phone shrinks the answer column, never the line', () {
    for (final width in [390.0, 360.0, 320.0]) {
      final m = editorMetrics(
        width: width,
        answersVisible: true,
        wanted: 212,
      );
      final text = width - m.gutter - m.padH * 2 - m.answerW;
      expect(
        text,
        greaterThanOrEqualTo(200),
        reason: 'the line keeps 200px at $width',
      );
      expect(m.answerW, lessThan(212), reason: 'the column gives way at $width');
      expect(m.tight, isTrue);
    }

    // desktop is untouched: the stored width and the usual chrome
    final desk = editorMetrics(
      width: 1440,
      answersVisible: true,
      wanted: 212,
    );
    expect(desk.answerW, 212);
    expect(desk.gutter, 54);
    expect(desk.padH, 24);
    expect(desk.tight, isFalse);

    // answers hidden: the text gets the whole pane
    final none = editorMetrics(
      width: 390,
      answersVisible: false,
      wanted: 212,
    );
    expect(none.answerW, 0);
  });

  testWidgets('the format bar stays above the keyboard on a phone', (
    tester,
  ) async {
    await boot(tester, phone);
    await tester.enterText(
      find.descendant(
        of: find.byType(EditorView),
        matching: find.byType(TextField),
      ),
      'rent = 2500',
    );
    await tester.pump(const Duration(milliseconds: 60));

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(EditorView),
        matching: find.byType(TextField),
      ),
    );
    field.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('B'), findsOneWidget, reason: 'the bar is showing');

    // the software keyboard takes the bottom 300px of the screen
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump(const Duration(milliseconds: 60));
    final bar = tester.getRect(find.text('B'));
    expect(
      bar.bottom,
      lessThan(phone.height - 300),
      reason: 'the bar is above the keyboard, not under it',
    );
    tester.view.resetViewInsets();
  });

  testWidgets('tapping one pane does not scroll the other', (tester) async {
    await boot(tester, phone);
    await toggle(tester);
    await tester.enterText(fieldAt(0), List.filled(60, '1+1').join('\n'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(fieldAt(1), '2+2');
    await tester.pump(const Duration(milliseconds: 600));

    final a = tester.state<ScrollableState>(
      find
          .descendant(
            of: paneAt(0),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final b = tester.state<ScrollableState>(
      find
          .descendant(
            of: paneAt(1),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // the top pane was scrolled down by the caret reveal, the lower one is
    // still at its top: one pane's typing never moves the other
    expect(a.position.pixels, greaterThan(0));
    expect(b.position.pixels, 0);
  });
}
