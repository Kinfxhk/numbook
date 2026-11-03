import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';

/// The phone gutter used to be 32px with 14 reserved for the fold chevron,
/// leaving the digits 8px. "10" is wider than that, so it wrapped and the
/// second figure sat on the next line.
void main() {
  test('one phone digit keeps the 32px gutter', () {
    final m = editorMetrics(
      width: 390,
      answersVisible: true,
      wanted: 212,
      numberWidth: 6.6,
    );
    expect(m.gutter, 32);
    expect(m.tight, isTrue);
    expect(_lineRoom(390, m), greaterThanOrEqualTo(200));
  });

  test('two digits widen a phone gutter without taking the line', () {
    final phone = editorMetrics(
      width: 430,
      answersVisible: true,
      wanted: 212,
      numberWidth: 13.2,
    );
    expect(phone.gutter, greaterThan(32));
    expect(phone.gutter, lessThan(54));
    expect(phone.gutter, greaterThanOrEqualTo(14 + 13.2 + 10));
    expect(_lineRoom(430, phone), greaterThanOrEqualTo(200));

    // three digits, on the narrowest phone the suite cares about
    final narrow = editorMetrics(
      width: 320,
      answersVisible: true,
      wanted: 212,
      numberWidth: 22,
    );
    expect(narrow.gutter, greaterThan(phone.gutter));
    expect(_lineRoom(320, narrow), greaterThanOrEqualTo(200));
  });

  test('a desktop gutter stays 54 while the digits still fit', () {
    final m = editorMetrics(
      width: 1440,
      answersVisible: true,
      wanted: 212,
      numberWidth: 13.2,
    );
    expect(m.gutter, 54);
    expect(m.answerW, 212);
    expect(m.tight, isFalse);
  });

  testWidgets('two-digit line numbers stay intact on a phone', (tester) async {
    final field = await _boot(tester, const Size(430, 932));
    await tester.enterText(field, List.filled(12, '1').join('\n'));
    await tester.pump(const Duration(milliseconds: 80));

    _expectFullNumber(tester, '9', field);
    _expectFullNumber(tester, '10', field);
    _expectFullNumber(tester, '12', field);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hundred lines stay intact, and the chevron stays clear', (
    tester,
  ) async {
    final field = await _boot(tester, const Size(360, 780));
    final lines = List<String>.generate(100, (i) => i == 9 ? '# section' : '1');
    await tester.enterText(field, lines.join('\n'));
    await tester.pump(const Duration(milliseconds: 80));

    _expectFullNumber(tester, '10', field);
    _expectFullNumber(tester, '100', field);

    final number = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('gutter-10')),
    );
    final box = number
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 2),
        )
        .single;
    final glyphLeft = number.localToGlobal(Offset(box.left, 0)).dx;
    final arrow = tester.getRect(
      find.descendant(
        of: find.byType(EditorView),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
    );
    expect(arrow.right, lessThanOrEqualTo(glyphLeft + 0.5));
    expect(tester.takeException(), isNull);
  });
}

double _lineRoom(double width, EditorMetrics m) =>
    width - m.gutter - m.padH * 2 - m.answerW;

Future<Finder> _boot(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const TallynoteApp());
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
  return find.descendant(
    of: find.byType(EditorView),
    matching: find.byType(TextField),
  );
}

void _expectFullNumber(WidgetTester tester, String label, Finder field) {
  final render = tester.renderObject<RenderParagraph>(
    find.byKey(ValueKey('gutter-$label')),
  );
  expect(render.text.toPlainText(), label, reason: 'gutter $label');
  expect(render.didExceedMaxLines, isFalse, reason: '$label is clipped');
  expect(render.size.height, lessThan(20), reason: '$label wraps');
  expect(
    render.size.width,
    greaterThanOrEqualTo(render.getMaxIntrinsicWidth(double.infinity) - 0.01),
    reason: '$label is narrower than its glyphs',
  );
  final boxes = render.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: label.length),
  );
  expect(boxes, hasLength(1), reason: '$label stays on one line');
  final glyphRight = render.localToGlobal(Offset(boxes.single.right, 0)).dx;
  expect(
    glyphRight,
    lessThanOrEqualTo(tester.getTopLeft(field).dx + 0.5),
    reason: '$label overlaps the line',
  );
}
