import 'package:flutter/material.dart';

import 'theme.dart';

/// Notebook ruling under the editor text. Plain is the legacy look.
enum PaperStyle { plain, single, double }

PaperStyle paperStyleFrom(String? key) => switch (key) {
  'single' => PaperStyle.single,
  'double' => PaperStyle.double,
  _ => PaperStyle.plain,
};

String paperStyleKey(PaperStyle style) => switch (style) {
  PaperStyle.single => 'single',
  PaperStyle.double => 'double',
  PaperStyle.plain => 'plain',
};

/// Strut shared by [TextField] and [measureEditorTextLayout].
StrutStyle editorStrutStyle({required double scale}) => StrutStyle(
  fontFamily: monoFamily,
  fontSize: 15 * scale,
  height: 28 / 15,
  forceStrutHeight: true,
  leadingDistribution: TextLeadingDistribution.even,
);

const editorTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: true,
  applyHeightToLastDescent: true,
);

/// One painted row of glyphs (a soft-wrapped segment counts as its own row).
@immutable
class VisualLineMetric {
  final double top;
  final double height;

  const VisualLineMetric({required this.top, required this.height});

  double get bottom => top + height;
}

/// Vertical span of one logical `\n`-delimited line, including wraps.
@immutable
class LogicalLineSpan {
  final int index;
  final double top;
  final double height;

  const LogicalLineSpan({
    required this.index,
    required this.top,
    required this.height,
  });

  double get bottom => top + height;
}

/// Measured editor geometry for answers, gutter, paper, and caret reveal.
@immutable
class EditorTextLayout {
  final List<double> logicalLineTops;
  final List<VisualLineMetric> visualLines;
  final List<LogicalLineSpan> logicalLines;
  final double rowHeight;

  const EditorTextLayout({
    required this.logicalLineTops,
    required this.visualLines,
    required this.logicalLines,
    required this.rowHeight,
  });

  double get contentHeight =>
      visualLines.isEmpty ? rowHeight : visualLines.last.bottom;
}

EditorTextLayout measureEditorTextLayout({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required double scale,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final strut = editorStrutStyle(scale: scale);
  final painter = TextPainter(
    text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    strutStyle: strut,
    textHeightBehavior: editorTextHeightBehavior,
  )..layout(maxWidth: maxWidth);

  final visualLines = <VisualLineMetric>[
    for (final m in painter.computeLineMetrics())
      VisualLineMetric(top: m.baseline - m.ascent, height: m.height),
  ];

  final rowHeight = painter.preferredLineHeight;
  final logicalLineTops = <double>[];
  final logicalLines = <LogicalLineSpan>[];
  final lines = text.split('\n');
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final start = offset;
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: start),
      Rect.zero,
    );
    logicalLineTops.add(caret.dy);
    offset += line.length + 1;
  }
  for (var i = 0; i < logicalLineTops.length; i++) {
    final top = logicalLineTops[i];
    final bottom = i + 1 < logicalLineTops.length
        ? logicalLineTops[i + 1]
        : painter.height;
    logicalLines.add(LogicalLineSpan(index: i, top: top, height: bottom - top));
  }

  painter.dispose();

  return EditorTextLayout(
    logicalLineTops: logicalLineTops,
    visualLines: visualLines,
    logicalLines: logicalLines,
    rowHeight: rowHeight,
  );
}

/// Paints ruled lines and optional current-line tint inside the editor stack.
class EditorPaperPainter extends CustomPainter {
  EditorPaperPainter({
    required this.dark,
    required this.paperStyle,
    required this.layout,
    required this.highlightLogicalLine,
    required this.highlightEnabled,
    required this.textLeft,
    required this.scrollOffset,
    required this.viewportHeight,
    this.buffer = 48,
  });

  final bool dark;
  final PaperStyle paperStyle;
  final EditorTextLayout layout;
  final int? highlightLogicalLine;
  final bool highlightEnabled;
  final double textLeft;
  final double scrollOffset;
  final double viewportHeight;
  final double buffer;

  @override
  void paint(Canvas canvas, Size size) {
    if (paperStyle == PaperStyle.plain && !highlightEnabled) return;

    final rule = Palette.hairline(dark);
    final rulePaint = Paint()
      ..color = rule
      ..strokeWidth = 1;

    if (highlightEnabled && highlightLogicalLine != null) {
      final idx = highlightLogicalLine!;
      if (idx >= 0 && idx < layout.logicalLines.length) {
        final span = layout.logicalLines[idx];
        final rect = Rect.fromLTWH(
          textLeft,
          span.top,
          size.width - textLeft,
          span.height,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = Palette.answer(dark)
                .withValues(alpha: dark ? 0.12 : 0.08),
        );
      }
    }

    if (paperStyle == PaperStyle.plain) return;

    final low = scrollOffset - buffer;
    final high = scrollOffset + viewportHeight + buffer;
    final contentH = layout.contentHeight;

    void strokeRule(double y) {
      canvas.drawLine(Offset(textLeft, y), Offset(size.width, y), rulePaint);
    }

    // Binary seek avoids walking the whole document on every scroll frame.
    var start = 0;
    var end = layout.visualLines.length;
    while (start < end) {
      final mid = (start + end) ~/ 2;
      if (layout.visualLines[mid].bottom < low) {
        start = mid + 1;
      } else {
        end = mid;
      }
    }
    for (var i = start; i < layout.visualLines.length; i++) {
      final row = layout.visualLines[i];
      if (row.top > high) break;
      strokeRule(row.bottom - 0.5);
      if (paperStyle == PaperStyle.double) {
        strokeRule(row.bottom - 4.5);
      }
    }

    // Blank tail: extend baselines without changing scroll extent.
    if (high > contentH) {
      var y = contentH + layout.rowHeight;
      if (y < low) {
        y += ((low - y) / layout.rowHeight).ceil() * layout.rowHeight;
      }
      while (y < high) {
        if (y >= low) {
          strokeRule(y - 0.5);
          if (paperStyle == PaperStyle.double) {
            strokeRule(y - 4.5);
          }
        }
        y += layout.rowHeight;
      }
    }
  }

  @override
  bool shouldRepaint(covariant EditorPaperPainter oldDelegate) {
    return dark != oldDelegate.dark ||
        paperStyle != oldDelegate.paperStyle ||
        highlightLogicalLine != oldDelegate.highlightLogicalLine ||
        highlightEnabled != oldDelegate.highlightEnabled ||
        textLeft != oldDelegate.textLeft ||
        scrollOffset != oldDelegate.scrollOffset ||
        viewportHeight != oldDelegate.viewportHeight ||
        layout != oldDelegate.layout;
  }
}
