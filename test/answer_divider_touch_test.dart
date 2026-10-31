import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_pane.dart';
import 'package:tallynote/ui/editor_view.dart';

/// The rule between text and answers has to answer a thumb: a swipe, a stream
/// of pointer moves, and a hold-then-pull all move it, and none of them hands
/// the gesture to the caret.
const tablet = Size(800, 1000);

Finder editor() => find.descendant(
  of: find.byType(EditorView),
  matching: find.byType(TextField),
);

Finder divider() => find.byKey(const ValueKey('answer-divider'));

/// The 1px rule, not the 44dp band around it.
Finder hairline() => find.descendant(
  of: divider(),
  matching: find.byWidgetPredicate(
    (w) => w is Container && w.constraints?.maxWidth == 1,
  ),
);

double ruleX(WidgetTester tester) => tester.getCenter(hairline()).dx;

PaneState pane(WidgetTester tester) =>
    tester.widget<EditorPane>(find.byType(EditorPane).first).pane;

TextSelection selection(WidgetTester tester) =>
    tester.widget<TextField>(editor()).controller!.selection;

/// A phone is the only place the band is 44dp and the grip is drawn.
Future<void> boot(WidgetTester tester, Size size) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const TallynoteApp());
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> done(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = null;
  await tester.pump();
}

Future<void> withAnswer(WidgetTester tester) async {
  await tester.enterText(editor(), '2000+3000');
  await tester.pump(const Duration(milliseconds: 400));
}

/// A finger that lands on the rule and travels [dx]. Nothing happens until the
/// touch slop is passed, exactly as on a device.
Future<TestGesture> pull(
  WidgetTester tester,
  double dx, {
  Duration hold = Duration.zero,
}) async {
  final band = tester.getRect(divider());
  final g = await tester.startGesture(
    band.center,
    kind: PointerDeviceKind.touch,
  );
  if (hold > Duration.zero) await tester.pump(hold);
  const steps = 6;
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(dx / steps, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 200));
  return g;
}

void main() {
  testWidgets('a thumb swipe moves the rule', (tester) async {
    await boot(tester, tablet);
    await withAnswer(tester);
    final before = ruleX(tester);

    final g = await pull(tester, -120);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      ruleX(tester),
      lessThan(before - 40),
      reason: 'dragging left widens the answer column',
    );
    expect(
      selection(tester).isCollapsed,
      isTrue,
      reason: 'the editor never saw the pointer: no selection drag',
    );
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ruleX(tester), lessThan(before - 40), reason: 'and it stays there');
    await done(tester);
  });

  testWidgets('a move-by-move drag moves it too, and selects nothing', (
    tester,
  ) async {
    await boot(tester, tablet);
    await withAnswer(tester);
    final before = ruleX(tester);

    // the shape `adb shell input motionevent DOWN/MOVE…/UP` produces
    final band = tester.getRect(divider());
    final g = await tester.startGesture(
      band.center,
      kind: PointerDeviceKind.touch,
    );
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset(band.center.dx - i * 15, band.center.dy));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(ruleX(tester), lessThan(before - 40));
    expect(selection(tester).isCollapsed, isTrue);
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    await done(tester);
  });

  testWidgets('press, hold, then drag moves it — the thumb gesture', (
    tester,
  ) async {
    await boot(tester, tablet);
    await withAnswer(tester);
    final before = ruleX(tester);

    final g = await pull(tester, -150, hold: const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      ruleX(tester),
      lessThan(before - 40),
      reason: 'a held finger is still a grab, not a text selection',
    );
    expect(selection(tester).isCollapsed, isTrue);
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    await done(tester);
  });

  testWidgets('the band is opaque: a tap on it does not move the caret', (
    tester,
  ) async {
    await boot(tester, tablet);
    await withAnswer(tester);
    final caret = selection(tester).baseOffset;

    await tester.tapAt(tester.getCenter(divider()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(tester).baseOffset, caret);
    expect(selection(tester).isCollapsed, isTrue);
    await done(tester);
  });

  testWidgets('an empty note still moves the rule, and keeps the width', (
    tester,
  ) async {
    await boot(tester, tablet);
    final before = ruleX(tester);

    // an empty column sits at its cap, so pulling right is what moves it
    final g = await pull(tester, 40);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ruleX(tester), greaterThan(before + 10));
    expect(pane(tester).answerW, lessThan(212));
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));

    // the first answer uses the width the empty note was pulled to
    await tester.enterText(editor(), '2500');
    await tester.pump(const Duration(milliseconds: 400));
    expect(ruleX(tester), greaterThan(before));
    await done(tester);
  });

  testWidgets('a grip appears on the rule while the pane has the caret', (
    tester,
  ) async {
    await boot(tester, tablet);
    Finder grip() => find.descendant(
      of: divider(),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 2,
      ),
    );
    expect(grip(), findsNothing, reason: 'no caret, no grip');

    await tester.tap(editor());
    await tester.pump(const Duration(milliseconds: 200));
    final box = tester.getRect(grip());
    expect(box.width, 2);
    expect(box.height, 24);
    expect(box.center.dx, closeTo(ruleX(tester), 1.5));

    pane(tester).focus.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
    expect(grip(), findsNothing, reason: 'no caret, no grip');
    await done(tester);
  });
}
