import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';
import 'package:tallynote/ui/key_bar.dart';
import 'package:tallynote/ui/marked_controller.dart';

/// The key bar exists because a phone IME cannot type `+ − × ÷`: every chip
/// writes into the editor's controller directly.
void main() {
  late MarkedController c;

  setUp(() {
    c = MarkedController(text: 'rent = 2500', dark: false);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => c.dispose());

  Future<void> pumpBar(WidgetTester tester, {bool dark = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KeyBar(controller: c, dark: dark)),
      ),
    );
  }

  /// The caret goes where the user left it, not at the end.
  void caretAt(int offset) {
    c.selection = TextSelection.collapsed(offset: offset);
  }

  testWidgets('a chip inserts at the caret', (tester) async {
    await pumpBar(tester);
    caretAt(8);
    await tester.tap(find.text('+'));
    await tester.pump();

    expect(c.text, 'rent = 2+500');
    expect(c.selection.baseOffset, 9, reason: 'the caret follows the insert');
  });

  testWidgets('the words page swaps in with one chip', (tester) async {
    await pumpBar(tester);
    expect(find.text('usd'), findsNothing);

    await tester.tap(find.text('A'));
    await tester.pump();
    expect(find.text('usd'), findsOneWidget);
    // the conversion word lives in the bar too: an IME that composes latin
    // into hanzi can neither type `to` nor `兌`
    expect(find.text('to'), findsOneWidget);
    expect(find.text('兌'), findsOneWidget);
    expect(find.text('+'), findsNothing);

    // the page is wider than the screen: the tail is a scroll away
    await tester.drag(find.text('usd'), const Offset(-400, 0));
    await tester.pump();
    expect(find.text('打八折'), findsOneWidget);
    await tester.drag(find.text('打八折'), const Offset(400, 0));
    await tester.pump();

    caretAt(11);
    await tester.tap(find.text('usd'));
    await tester.pump();
    // a word chip carries its own space, so chips chain into "5000usd to hkd"
    // without the IME ever leaving Chinese
    expect(c.text, 'rent = 2500usd ');

    // and back to the symbols
    await tester.tap(find.text('123'));
    await tester.pump();
    expect(find.text('+'), findsOneWidget);
  });

  testWidgets('⌫ deletes one character and ↵ adds a line', (tester) async {
    await pumpBar(tester);
    caretAt(5);
    await tester.tap(find.text('⌫'));
    await tester.pump();
    expect(c.text, 'rent= 2500', reason: 'the space before the caret');
    expect(c.selection.baseOffset, 4);

    await tester.tap(find.text('↵'));
    await tester.pump();
    expect(c.text, 'rent\n= 2500');
    expect(c.selection.baseOffset, 5);

    // at the very start there is nothing left to delete
    caretAt(0);
    await tester.tap(find.text('⌫'));
    await tester.pump();
    expect(c.text, 'rent\n= 2500');
  });

  testWidgets('a selection is replaced, not appended', (tester) async {
    await pumpBar(tester);
    c.selection = const TextSelection(baseOffset: 7, extentOffset: 11);
    await tester.tap(find.text('='));
    await tester.pump();
    expect(c.text, 'rent = =');
  });

  testWidgets('the bar is 44dp and only drawn from chips', (tester) async {
    await pumpBar(tester);
    expect(tester.getSize(find.byType(KeyBar)).height, 44);
    // no icons: ⌫ and ↵ are glyphs, like every other chip
    expect(find.byIcon(Icons.backspace), findsNothing);
    expect(find.text('⌫'), findsOneWidget);
    expect(find.text('↵'), findsOneWidget);
  });

  group('in the app', () {
    Future<void> boot(
      WidgetTester tester, {
      Size size = const Size(390, 844),
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

    Finder editor() => find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );

    testWidgets('shows above the keyboard, and only then', (tester) async {
      await boot(tester);
      expect(find.byType(KeyBar), findsNothing, reason: 'no focus, no keys');

      await tester.tap(editor());
      await tester.pump();
      expect(
        find.byType(KeyBar),
        findsNothing,
        reason: 'focus without a soft keyboard is a desktop',
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(find.byType(KeyBar), findsOneWidget);

      // the bar sits above the keyboard, not under it
      expect(
        tester.getRect(find.byType(KeyBar)).bottom,
        lessThanOrEqualTo(844 - 300),
      );

      // typing through a chip reaches the sheet
      await tester.tap(find.text('+'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widget<TextField>(editor()).controller!.text, '+');

      tester.view.resetViewInsets();
      await tester.pump();
      expect(find.byType(KeyBar), findsNothing, reason: 'keyboard gone');
    });

    testWidgets('the setting turns it off', (tester) async {
      await boot(tester, prefs: {'tallynote.keyBar': false});
      await tester.tap(editor());
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(find.byType(KeyBar), findsNothing);
      tester.view.resetViewInsets();
    });

    testWidgets('the Editor settings tab carries the switch', (tester) async {
      await boot(tester, size: const Size(1440, 900));
      await tester.tap(find.byTooltip('Settings').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const ValueKey('switch-keyBar'));
      if (switchFinder.evaluate().isEmpty) {
        await tester.drag(
          find.descendant(of: find.byType(Dialog), matching: find.byType(ListView)).first,
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Calculation keys'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('switch-keyBar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.tap(editor());
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(find.byType(KeyBar), findsNothing, reason: 'switched off');
      tester.view.resetViewInsets();
    });
  });
}
