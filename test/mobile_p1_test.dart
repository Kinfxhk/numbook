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
import 'package:tallynote/ui/feedback.dart';
import 'package:tallynote/ui/key_bar.dart';
import 'package:tallynote/ui/sidebar.dart';

/// The 0.5.0 phone pass: the gestures the phone was missing (swipe, the split
/// divider, fold-all, a reference at the caret, the gutter) and the polish
/// around them (haptics, bottom sheets, the drawer's thumb reach, the gesture
/// inset, landscape, a theme that follows the system).
const phone = Size(390, 844);
const landscape = Size(792, 363);
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

Map<String, Object> withText(String text) => {
  'tallynote.sheets.v1': jsonEncode({
    'v': 2,
    'folders': [],
    'sheets': [
      {
        'id': 'a',
        'title': 'Alpha',
        'content': text,
        'pinned': false,
        'customTitle': true,
        'updated': '2026-01-02T00:00:00.000',
      },
      {
        'id': 'b',
        'title': 'Beta',
        'content': '',
        'pinned': false,
        'customTitle': true,
        'updated': '2026-01-01T00:00:00.000',
      },
    ],
  }),
  'tallynote.active.v1': 'a',
};

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

Finder fieldIn(EditorPane pane) => find.descendant(
  of: find.byWidget(pane),
  matching: find.byType(TextField),
);

Finder editorAt(int i) => find.descendant(
  of: find.byType(EditorPane).at(i),
  matching: find.byType(TextField),
);

Finder editor() => find.descendant(
  of: find.byType(EditorView),
  matching: find.byType(TextField),
);

String textOf(WidgetTester tester, Finder f) =>
    tester.widget<TextField>(f).controller!.text;

double paneWidth(WidgetTester tester, int i) =>
    tester.getSize(find.byType(EditorPane).at(i)).width;

double paneHeight(WidgetTester tester, int i) =>
    tester.getSize(find.byType(EditorPane).at(i)).height;

void main() {
  group('a sheet row', () {
    testWidgets('swipes left to delete, and undo brings the sheet back', (
      tester,
    ) async {
      await boot(tester, desktop, prefs: twoSheets());
      final row = find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('Beta'),
      );
      expect(row, findsOneWidget);

      await tester.drag(row, const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(row, findsNothing, reason: 'the row is gone');
      expect(find.text('Sheet deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // the same sheet, id and text included
      expect(row, findsOneWidget);
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 60));
      expect(textOf(tester, editor()), 'seed');
    });

    testWidgets('swipes right to pin, without removing the row', (
      tester,
    ) async {
      await boot(tester, desktop, prefs: twoSheets());
      expect(find.byIcon(Icons.push_pin), findsNothing);
      final row = find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('Beta'),
      );

      await tester.drag(row, const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(row, findsOneWidget, reason: 'a pin is not delete');
      final stored = (await SharedPreferences.getInstance()).getString(
        'tallynote.sheets.v1',
      )!;
      expect(stored, contains('"id":"b","title":"Beta"'));
      expect(
        RegExp(r'"id":"b".*?"pinned":true').hasMatch(stored) ||
            RegExp(r'"pinned":true[^}]*"id":"b"').hasMatch(stored),
        isTrue,
        reason: 'Beta is pinned in the store',
      );
    });

    testWidgets('a phone keeps the undo bar on screen', (tester) async {
      await boot(tester, phone, prefs: twoSheets());
      await tester.tap(find.byIcon(Icons.menu).first);
      await tester.pumpAndSettle();

      await tester.drag(
        find.descendant(of: find.byType(Sidebar), matching: find.text('Beta')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      // the drawer steps aside, or it would cover the undo
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      expect(scaffold.isDrawerOpen, isFalse);
      expect(find.text('Undo'), findsOneWidget);
    });
  });

  group('the split divider', () {
    testWidgets('drags the ratio, clamps it, and remembers it', (
      tester,
    ) async {
      await boot(tester, desktop, prefs: twoSheets());
      await tester.tap(find.byIcon(Icons.vertical_split));
      await tester.pump(const Duration(milliseconds: 60));

      final divider = find.byKey(const ValueKey('split-divider'));
      expect(divider, findsOneWidget);
      final even = paneWidth(tester, 0);

      await tester.drag(divider, const Offset(-200, 0));
      await tester.pump(const Duration(milliseconds: 60));
      expect(paneWidth(tester, 0), lessThan(even - 100));

      final dragged = paneWidth(tester, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('tallynote.splitRatio'), isNot(0.5));

      // a pane never disappears: 15% is the floor, and it is written down
      await tester.drag(divider, const Offset(-2000, 0));
      await tester.pump(const Duration(milliseconds: 60));
      expect(paneWidth(tester, 0), greaterThan(100));
      expect(paneWidth(tester, 0), lessThan(dragged));

      expect(
        (await SharedPreferences.getInstance()).getDouble(
          'tallynote.splitRatio',
        ),
        0.15,
        reason: 'the drag end writes it down, clamped',
      );
    });

    testWidgets('a double tap goes back to 50/50', (tester) async {
      await boot(tester, desktop, prefs: {...twoSheets(), 'tallynote.splitRatio': 0.3});
      await tester.tap(find.byIcon(Icons.vertical_split));
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        paneWidth(tester, 0),
        lessThan(paneWidth(tester, 1)),
        reason: 'the stored ratio is honoured',
      );

      await tester.tap(find.byKey(const ValueKey('split-divider')));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.byKey(const ValueKey('split-divider')));
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        paneWidth(tester, 0),
        closeTo(paneWidth(tester, 1), 2),
        reason: 'dragging one hairline back is not a hit target',
      );
    });

    testWidgets('a long press swaps the two panes', (tester) async {
      await boot(tester, desktop, prefs: twoSheets());
      await tester.tap(find.byIcon(Icons.vertical_split));
      await tester.pump(const Duration(milliseconds: 60));
      expect(textOf(tester, editorAt(0)), isNot('seed'));
      expect(textOf(tester, editorAt(1)), 'seed');

      await tester.longPress(find.byKey(const ValueKey('split-divider')));
      await tester.pump(const Duration(milliseconds: 60));

      expect(textOf(tester, editorAt(0)), 'seed');
      expect(textOf(tester, editorAt(1)), isNot('seed'));
    });

    testWidgets('a stacked phone drags vertically', (tester) async {
      await boot(tester, phone, prefs: twoSheets());
      await tester.tap(find.byIcon(Icons.vertical_split));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('split-column')), findsOneWidget);

      final before = paneHeight(tester, 0);
      await tester.drag(
        find.byKey(const ValueKey('split-divider')),
        const Offset(0, -80),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(paneHeight(tester, 0), lessThan(before));
    });
  });

  group('folding', () {
    testWidgets('a long press on a chevron folds everything, then unfolds', (
      tester,
    ) async {
      await boot(tester, desktop, prefs: withText('# A\n100\n200\n# B\n300\n400'));
      await tester.pump(const Duration(milliseconds: 80));

      Finder chevron(IconData i) =>
          find.descendant(of: find.byType(EditorView), matching: find.byIcon(i));
      expect(chevron(Icons.keyboard_arrow_down), findsNWidgets(2));

      await tester.longPress(chevron(Icons.keyboard_arrow_down).first);
      await tester.pump(const Duration(milliseconds: 80));

      var field = tester.widget<TextField>(editor());
      expect(field.controller!.text, isNot(contains('200')));
      expect(field.controller!.text, isNot(contains('400')));
      expect(field.readOnly, isTrue);

      await tester.longPress(chevron(Icons.keyboard_arrow_right).first);
      await tester.pump(const Duration(milliseconds: 80));

      field = tester.widget<TextField>(editor());
      expect(field.controller!.text, contains('200'));
      expect(field.controller!.text, contains('400'));
      expect(field.readOnly, isFalse);
    });
  });

  group('the gutter and the answers', () {
    testWidgets('a double tap puts the reference at the caret', (tester) async {
      await boot(tester, desktop, prefs: withText('2500\n3000'));
      await tester.pump(const Duration(milliseconds: 80));

      final c = tester.widget<TextField>(editor()).controller!;
      c.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump(const Duration(milliseconds: 20));

      final answer = find.text('3,000');
      expect(answer, findsOneWidget);
      await tester.tap(answer);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(answer);
      await tester.pump(const Duration(milliseconds: 60));

      expect(c.text, 'line 22500\n3000', reason: 'at the caret, not the end');
      expect(c.selection.baseOffset, 'line 2'.length);
    });

    testWidgets('a tap on a line number selects the line', (tester) async {
      await boot(tester, desktop, prefs: withText('100\n200\n300'));
      await tester.pump(const Duration(milliseconds: 80));

      await tester.tap(find.byKey(const ValueKey('gutter-2')));
      await tester.pump(const Duration(milliseconds: 60));

      final c = tester.widget<TextField>(editor()).controller!;
      expect(c.selection.baseOffset, 4);
      expect(c.selection.extentOffset, 7);
      expect(c.text.substring(c.selection.start, c.selection.end), '200');
    });

    testWidgets('a long press on a line number folds the section', (tester) async {
      await boot(tester, desktop, prefs: withText('# A\n100\n200'));
      await tester.pump(const Duration(milliseconds: 80));

      await tester.longPress(find.byKey(const ValueKey('gutter-1')));
      await tester.pump(const Duration(milliseconds: 80));

      final field = tester.widget<TextField>(editor());
      expect(field.controller!.text, isNot(contains('200')));
      expect(field.readOnly, isTrue);
    });
  });

  group('menus', () {
    testWidgets('a phone gets a bottom sheet, a desktop the popup', (
      tester,
    ) async {
      await boot(tester, phone, prefs: twoSheets());
      await tester.tap(find.byIcon(Icons.vertical_split));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(PopupMenuButton<String>), findsNothing);

      // the pane's chevron is a 26dp row, so tap the icon itself
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).last);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      // rows a thumb can hit
      final rows = tester
          .widgetList<ConstrainedBox>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(ConstrainedBox),
            ),
          )
          .map((w) => w.constraints.minHeight)
          .where((h) => h.isFinite && h > 0);
      expect(rows, everyElement(greaterThanOrEqualTo(48)));
      await tester.tapAt(const Offset(20, 40));
      await tester.pumpAndSettle();
    });

    testWidgets('a desktop keeps the popup', (tester) async {
      await boot(tester, desktop, prefs: twoSheets());
      await tester.tap(find.byIcon(Icons.vertical_split));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(PopupMenuButton<String>), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).last);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(PopupMenuItem<String>), findsWidgets);
      await tester.tapAt(const Offset(20, 40));
      await tester.pumpAndSettle();
    });
  });

  group('haptics', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      Haptics.on = true;
    });
    tearDown(() {
      Haptics.on = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    int ticks() => calls.where((c) => c.method == 'HapticFeedback.vibrate').length;

    testWidgets('a key-bar chip ticks, and the setting silences it', (
      tester,
    ) async {
      await boot(tester, phone, prefs: twoSheets());

      // the switch lives beside the other editor settings
      await tester.tap(find.byTooltip('Settings').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('switch-haptics')),
        find
            .descendant(of: find.byType(Dialog), matching: find.byType(ListView))
            .first,
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('switch-haptics')));
      await tester.pumpAndSettle();
      expect(Haptics.on, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tallynote.haptics'), isFalse);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // and a chip now makes no tick at all
      await tester.tap(editor());
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(find.byType(KeyBar), findsOneWidget);

      calls.clear();
      await tester.tap(find.text('+'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(ticks(), 0, reason: 'the switch is off');

      // and back on, it ticks again
      Haptics.on = true;
      calls.clear();
      await tester.tap(find.text('×'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(ticks(), greaterThan(0));
      tester.view.resetViewInsets();
    });
  });

  testWidgets('the word chips alone can write a conversion', (tester) async {
    await boot(tester, phone, prefs: twoSheets());
    await tester.tap(editor());
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    await tester.enterText(editor(), '5000');
    await tester.pump(const Duration(milliseconds: 30));

    // the IME never leaves Chinese: every word comes from a chip
    await tester.tap(find.text('A'));
    await tester.pump();
    for (final word in ['usd', 'to', 'hkd']) {
      await tester.tap(find.text(word));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 60));

    expect(textOf(tester, editor()), '5000usd to hkd ');
    expect(
      find.textContaining('HK\$'),
      findsOneWidget,
      reason: 'the chips carry their own spaces, so the conversion parses',
    );
    tester.view.resetViewInsets();
  });

  testWidgets('the theme follows the system until it is told otherwise', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await boot(tester, desktop, prefs: {'tallynote.theme': 'system'});
    // the theme cross-fades; wait for it to land
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Sidebar))).brightness,
      Brightness.dark,
    );

    // a light phone is light again without touching the setting
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Sidebar))).brightness,
      Brightness.light,
    );
  });

  testWidgets('an android default follows the phone, a desktop stays light', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await boot(tester, phone, prefs: twoSheets());
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(EditorPane).first)).brightness,
      Brightness.dark,
      reason: 'no stored choice on a phone means follow the phone',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await boot(tester, desktop, prefs: twoSheets());
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(EditorPane).first)).brightness,
      Brightness.light,
      reason: 'desktop keeps the default it always had',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the key bar stays clear of the gesture inset', (tester) async {
    await boot(tester, phone, prefs: twoSheets());
    // a gesture-navigation bar: 24dp the app must not paint over
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);

    await tester.tap(editor());
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    final bar = tester.getRect(find.byType(KeyBar));
    expect(bar.bottom, lessThanOrEqualTo(844 - 24));
    tester.view.resetViewInsets();
    tester.view.resetPadding();
    await tester.pump();
    expect(find.byType(KeyBar), findsNothing);
  });

  testWidgets('landscape keeps the editor, so the key row gives way', (
    tester,
  ) async {
    await boot(tester, landscape, prefs: twoSheets());
    await tester.tap(editor());
    await tester.pump();
    // a landscape IME takes half the screen
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    await tester.pump();

    expect(find.byType(KeyBar), findsNothing, reason: 'no room for both');
    // 363 - 180 (IME) - 46 (header) - 26 (status): all of it is the editor
    expect(tester.getSize(find.byType(EditorView)).height, greaterThan(100));
    tester.view.resetViewInsets();
  });

  testWidgets('the editor settings tab fits a 390dp phone', (tester) async {
    await boot(tester, phone, prefs: twoSheets());
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    // a RenderFlex overflow is a thrown FlutterError, not a paint artefact
    expect(tester.takeException(), isNull);
    expect(find.text('Number format'), findsOneWidget);
  });
}
