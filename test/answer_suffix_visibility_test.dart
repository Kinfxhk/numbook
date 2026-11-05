import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/ui/answer_column.dart';

void main() {
  for (final display in ['11.0231 lb', '12.3456%', '3.5 km', '1.234,56 kg']) {
    testWidgets('fraction slot paints entire suffix for $display', (
      tester,
    ) async {
      final eu = display.contains(',');
      const style = TextStyle(
        inherit: false,
        fontFamily: 'monospace',
        fontSize: 16,
      );
      double width(String s) =>
          measureAnswerText(s, style, TextScaler.noScaling);
      final metrics = measureAnswers(
        [display],
        width,
        decimal: eu ? ',' : '.',
        group: eu ? '.' : ',',
        capFracW: width(eu ? ',9999' : '.9999'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 350,
              child: AnswerReadout(
                display: display,
                style: style,
                metrics: metrics,
                decimal: eu ? ',' : '.',
                group: eu ? '.' : ',',
              ),
            ),
          ),
        ),
      );
      final suffix = AnswerParts.parse(
        display,
        decimal: eu ? ',' : '.',
        group: eu ? '.' : ',',
      ).suffix;
      final text = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.contains(suffix),
      );
      expect(text, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason: 'the complete suffix glyphs must fit, not silently clip',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
