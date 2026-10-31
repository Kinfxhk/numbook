import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/answer_column.dart';
import 'package:tallynote/ui/editor_pane.dart';
import 'package:tallynote/ui/sidebar.dart';

/// Two sheets, both with a title of their own, so a rename cannot confuse
/// which pane is which.
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

/// Three sheets: a pane that loses its sheet has somewhere to fall back to.
Map<String, Object> threeSheets() => {
  'tallynote.sheets.v1': jsonEncode({
    'v': 2,
    'folders': [],
    'sheets': [
      for (final (id, title, day, text) in [
        ('a', 'Alpha', '03', 'alpha note'),
        ('b', 'Beta', '02', ''),
        ('c', 'Gamma', '01', ''),
      ])
        {
          'id': id,
          'title': title,
          'content': text,
          'pinned': false,
          'customTitle': true,
          'updated': '2026-01-${day}T00:00:00.000',
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

void main() {
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

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.vertical_split));
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('the header toggle opens and closes the second pane', (
    tester,
  ) async {
    await boot(tester, const Size(1440, 900), prefs: twoSheets());
    expect(find.byType(EditorPane), findsOneWidget);

    await toggle(tester);
    expect(find.byType(EditorPane), findsNWidgets(2));
    // the second pane opens its own sheet, text and all
    expect(tester.widget<TextField>(fieldAt(1)).controller!.text, 'seed');
    expect(tester.widget<TextField>(fieldAt(0)).controller!.text, '');

    await toggle(tester);
    expect(find.byType(EditorPane), findsOneWidget);
  });

  testWidgets('side by side on a wide window, stacked on a narrow one', (
    tester,
  ) async {
    await boot(tester, const Size(1440, 900), prefs: twoSheets());
    await toggle(tester);
    expect(find.byKey(const ValueKey('split-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('split-column')), findsNothing);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('split-column')), findsOneWidget);
    expect(find.byKey(const ValueKey('split-row')), findsNothing);
    expect(find.byType(EditorPane), findsNWidgets(2));
    // the header toggle stays reachable
    expect(find.byIcon(Icons.vertical_split), findsOneWidget);
  });

  testWidgets('each pane adds up on its own and saves its own sheet', (
    tester,
  ) async {
    await boot(tester, const Size(1440, 900), prefs: twoSheets());
    await toggle(tester);

    await tester.enterText(fieldAt(0), 'rent = 2500');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.enterText(fieldAt(1), '200*12');
    await tester.pump(const Duration(milliseconds: 600)); // both debounces

    expect(answerAt(0, '2,500'), findsOneWidget);
    expect(answerAt(0, '2,400'), findsNothing);
    expect(answerAt(1, '2,400'), findsOneWidget);
    expect(answerAt(1, '2,500'), findsNothing);

    // both panes wrote through the one save path, into their own sheet
    final prefs = await SharedPreferences.getInstance();
    final doc = jsonDecode(prefs.getString('tallynote.sheets.v1')!);
    final stored = {
      for (final s in (doc['sheets'] as List).cast<Map>())
        s['id'] as String: s['content'] as String,
    };
    expect(stored['a'], 'rent = 2500');
    expect(stored['b'], '200*12');
  });

  testWidgets('a sheet is never offered to, or opened in, both panes', (
    tester,
  ) async {
    await boot(tester, const Size(1440, 900), prefs: twoSheets());
    await toggle(tester);

    // the right pane's menu leaves out the sheet the left pane already shows
    await tester.tap(
      find.descendant(
        of: paneAt(1),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
    );
    await tester.pumpAndSettle();
    Finder menuText(String s) => find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.text(s),
    );
    expect(menuText('Alpha'), findsNothing);
    expect(menuText('Beta'), findsOneWidget);
    expect(menuText('New sheet'), findsOneWidget);
    await tester.tapAt(const Offset(700, 700)); // close the menu
    await tester.pumpAndSettle();

    // picking it in the sidebar moves the focus instead of duplicating it
    tester.widget<Sidebar>(find.byType(Sidebar)).store.select('b');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(EditorPane), findsNWidgets(2));
    expect(
      find.descendant(of: paneAt(0), matching: find.text('Alpha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: paneAt(1), matching: find.text('Beta')),
      findsOneWidget,
    );
  });

  testWidgets('the split and its second sheet come back after a restart', (
    tester,
  ) async {
    await boot(tester, const Size(1440, 900), prefs: twoSheets());
    await toggle(tester);
    await tester.enterText(fieldAt(1), '42');
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const ValueKey('split-row')), findsOneWidget);
    expect(find.byType(EditorPane), findsNWidgets(2));
    expect(
      find.descendant(of: paneAt(0), matching: find.text('Alpha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: paneAt(1), matching: find.text('Beta')),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(fieldAt(1)).controller!.text, '42');
  });

  testWidgets('closing the split inside the debounce keeps the newest text', (
    tester,
  ) async {
    await boot(tester, const Size(1440, 900), prefs: twoSheets());
    await toggle(tester);
    await tester.tap(fieldAt(1));
    await tester.enterText(fieldAt(1), 'newest 7');
    await tester.pump(const Duration(milliseconds: 100)); // still inside 400 ms
    await toggle(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(EditorPane), findsOneWidget);
    expect(tester.widget<TextField>(fieldAt(0)).controller!.text, 'newest 7');
  });

  testWidgets('a restart with the right pane focused keeps both sides', (
    tester,
  ) async {
    await boot(tester, const Size(1440, 900), prefs: twoSheets());
    await toggle(tester);
    await tester.tap(fieldAt(1));
    await tester.enterText(fieldAt(1), '42');
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.descendant(of: paneAt(0), matching: find.text('Alpha')),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(fieldAt(1)).controller!.text, '42');
  });

  testWidgets(
    'a pane whose sheet is deleted falls back, then the split closes',
    (tester) async {
      await boot(tester, const Size(1440, 900), prefs: threeSheets());
      await toggle(tester);
      expect(
        find.descendant(of: paneAt(1), matching: find.text('Beta')),
        findsOneWidget,
      );

      // a sidebar tap needs the haptic channel the test engine never answers,
      // so remove the sheets through the store the app itself is using
      final store = tester.widget<Sidebar>(find.byType(Sidebar)).store;

      store.delete('b'); // the right pane's sheet
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byType(EditorPane),
        findsNWidgets(2),
        reason: 'a third sheet',
      );
      expect(
        find.descendant(of: paneAt(1), matching: find.text('Gamma')),
        findsOneWidget,
      );

      store.delete('c'); // the last sheet the right pane could take
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(EditorPane), findsOneWidget, reason: 'nothing left');
      // the single pane is Alpha again, and it kept its text
      expect(
        tester.widget<TextField>(fieldAt(0)).controller!.text,
        'alpha note',
      );
    },
  );
}
