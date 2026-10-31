import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_pane.dart';
import 'package:tallynote/ui/editor_view.dart';

/// The phone work of 0.4.2: a column that does not eat the note, copy on a
/// long press, a finger-sized divider, BACK closing layers, and a save on tap.
const phone = Size(390, 844);
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

Finder editorAt(int i) => find.descendant(
  of: find.byType(EditorPane).at(i),
  matching: find.byType(TextField),
);

Finder editor() => find.descendant(
  of: find.byType(EditorView),
  matching: find.byType(TextField),
);

Future<void> boot(
  WidgetTester tester,
  Size size, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const TallynoteApp());
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
}

/// Android's BACK key, through the same route the platform uses.
Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
}

double dividerCentre(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('answer-divider'))).center.dx;

bool canPop(WidgetTester tester) {
  // PopScope is generic, so byType() matches nothing
  final scope = tester
      .widgetList(find.byWidgetPredicate((w) => w is PopScope))
      .first;
  return (scope as PopScope).canPop;
}

void main() {
  group('the answer column', () {
    test('an empty phone note clamps it to 120dp and 25%', () {
      for (final w in [363.0, 390.0, 412.0]) {
        final empty = editorMetrics(
          width: w,
          answersVisible: true,
          wanted: 212,
          hasAnswers: false,
        );
        expect(empty.answerW, lessThanOrEqualTo(120), reason: 'width $w');
        expect(empty.answerW, lessThanOrEqualTo(w * 0.25), reason: 'width $w');

        final answered = editorMetrics(
          width: w,
          answersVisible: true,
          wanted: 212,
        );
        expect(
          answered.answerW,
          greaterThan(empty.answerW),
          reason: 'the first answer gives the column back at $w',
        );
      }
    });

    test('desktop keeps its saved width on an empty note', () {
      final m = editorMetrics(
        width: 1440,
        answersVisible: true,
        wanted: 212,
        hasAnswers: false,
      );
      expect(m.answerW, 212);
    });

    testWidgets('a 390dp empty note shows the short hint', (tester) async {
      await boot(tester, phone);
      expect(
        find.text('Type a calculation…   e.g. 2500*12'),
        findsOneWidget,
        reason: 'one line, not the three-part sentence',
      );
      expect(
        find.textContaining('total of #food'),
        findsNothing,
        reason: 'the long hint belongs to a wide pane',
      );
    });

    testWidgets('the column is narrow while empty, then takes its width', (
      tester,
    ) async {
      await boot(tester, phone);
      // 390 - (97.5 + 12): the hint keeps its room, not 212dp
      expect(dividerCentre(tester), closeTo(390 - 109.5, 1));

      await tester.enterText(editor(), '2500');
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 300));

      // 390 - (134 + 12): the answer restores the saved width, capped by room
      expect(dividerCentre(tester), closeTo(390 - 146, 1));
    });
  });

  group('copy an answer', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    String? clipboard() => calls
        .where((c) => c.method == 'Clipboard.setData')
        .map((c) => (c.arguments as Map)['text'] as String?)
        .lastOrNull;

    testWidgets('a long press copies the number and says so', (tester) async {
      await boot(tester, phone);
      await tester.enterText(editor(), '1000*2+3000');
      await tester.pump(const Duration(milliseconds: 400));

      await tester.longPress(find.textContaining('5,000').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(clipboard(), '5,000');
      expect(find.text('Copied'), findsOneWidget);

      // the tap still expands the steps
      await tester.tap(find.textContaining('5,000').last);
      // a double tap now inserts a reference, so a single tap waits it out
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Steps'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('a right-click copies on a desktop', (tester) async {
      await boot(tester, desktop);
      await tester.enterText(editor(), '1000*2+3000');
      await tester.pump(const Duration(milliseconds: 400));

      final g = await tester.startGesture(
        tester.getCenter(find.textContaining('5,000').last),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(clipboard(), '5,000');
      expect(find.text('Copied'), findsOneWidget);
    });
  });

  group('the answer divider', () {
    testWidgets('is a 44dp finger target', (tester) async {
      await boot(tester, phone);
      final box = tester.getRect(find.byKey(const ValueKey('answer-divider')));
      expect(box.width, greaterThanOrEqualTo(44));
      // the hairline is still visible and still one pixel
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('answer-divider')),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxWidth == 1,
          ),
        ),
        findsWidgets,
      );
    });

    testWidgets('keeps the 10dp feel for a mouse', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await boot(tester, desktop);
      expect(
        tester.getSize(find.byKey(const ValueKey('answer-divider'))).width,
        10,
      );
      debugDefaultTargetPlatformOverride = null;
      await tester.pump();
    });

    testWidgets('still drags with the wider handle', (tester) async {
      await boot(tester, phone);
      await tester.enterText(editor(), '2000+3000');
      await tester.pump(const Duration(milliseconds: 400));
      final before = dividerCentre(tester);

      await tester.drag(
        find.byKey(const ValueKey('answer-divider')),
        const Offset(-30, 0),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(dividerCentre(tester), lessThan(before));
    });
  });

  group('BACK', () {
    testWidgets('closes the format bar first', (tester) async {
      await boot(tester, phone, prefs: twoSheets());
      await tester.enterText(editor(), 'hello world');
      await tester.pump(const Duration(milliseconds: 60));

      final c = tester.widget<TextField>(editor()).controller!;
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('B'), findsOneWidget, reason: 'the format bar is open');
      expect(canPop(tester), isFalse);

      await back(tester);
      expect(find.text('B'), findsNothing);
      expect(c.selection.isCollapsed, isTrue);
    });

    testWidgets('closes the drawer next', (tester) async {
      await boot(tester, phone, prefs: twoSheets());
      await tester.tap(find.byIcon(Icons.menu).first);
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      expect(scaffold.isDrawerOpen, isTrue);

      await back(tester);
      await tester.pumpAndSettle();
      expect(scaffold.isDrawerOpen, isFalse);
    });

    testWidgets('closes the split, keeping the focused pane', (tester) async {
      await boot(tester, phone, prefs: twoSheets());
      await tester.tap(find.byIcon(Icons.vertical_split));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(EditorPane), findsNWidgets(2));
      expect(canPop(tester), isFalse);

      await back(tester);
      expect(find.byType(EditorPane), findsOneWidget);
      // the pane that stays is the one that had focus: sheet 'a', still empty
      expect(
        tester.widget<TextField>(editorAt(0)).controller!.text,
        isNot('seed'),
      );
    });

    testWidgets('drops the keyboard, then lets the app go', (tester) async {
      await boot(tester, phone, prefs: twoSheets());
      await tester.tap(editor());
      await tester.pump(const Duration(milliseconds: 60));
      final focus = FocusManager.instance.primaryFocus;
      expect(canPop(tester), isFalse, reason: 'the keyboard is up');

      await back(tester);
      expect(
        focus?.hasFocus,
        isFalse,
        reason: 'BACK only closes the keyboard',
      );

      expect(canPop(tester), isTrue, reason: 'nothing left: leave the app');
    });
  });

  testWidgets('tapping the save state saves now', (tester) async {
    await boot(tester, desktop);
    await tester.enterText(editor(), '1+1');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('editing'), findsOneWidget);

    await tester.tap(find.textContaining('editing'));
    await tester.pump();
    expect(find.text('Saved ✓'), findsOneWidget, reason: 'no waiting 400ms');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tallynote.sheets.v1'), contains('1+1'));

    await tester.pump(const Duration(seconds: 2));
  });
}
