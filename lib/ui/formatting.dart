import 'package:flutter/material.dart';

import '../engine/lexer.dart';

/// Lightweight inline formatting.
///
/// Markers live in the plain text, so a sheet stays a text file and the
/// engine can still read the line after [stripMarkers]. No selection model,
/// no rich-text document: just markers rendered by the text controller.
///
///   **bold**   _italic_   ~~strike~~   __underline__   {red}coloured{/}
class Fmt {
  static const colours = <String, Color>{
    'red': Color(0xFFA8442B),
    'orange': Color(0xFFC2703A),
    'green': Color(0xFF4F7A45),
    'blue': Color(0xFF3C6E9E),
    'grey': Color(0xFF8A8578),
  };

  static const Map<String, String> _openToClose = {
    '**': '**',
    '__': '__',
    '~~': '~~',
    '_': '_',
  };

  /// Removes every marker so the engine sees plain arithmetic.
  static String stripMarkers(String s) => stripInlineMarkers(s);

  /// Turns one line into styled spans. Unmatched markers are shown as text.
  static List<TextSpan> spans(
    String text,
    TextStyle base, {
    bool cursor = false,
  }) {
    final spans = <TextSpan>[];
    var style = base;
    final buf = StringBuffer();
    var i = 0;

    void flush() {
      if (buf.isNotEmpty) {
        spans.add(TextSpan(text: buf.toString(), style: style));
        buf.clear();
      }
    }

    while (i < text.length) {
      // colour open: {red}
      final colour = RegExp(r'^\{(' + colours.keys.join('|') + r')\}')
          .firstMatch(text.substring(i));
      if (colour != null) {
        flush();
        style = style.copyWith(color: colours[colour[1]]);
        i += colour[0]!.length;
        continue;
      }
      if (text.startsWith('{/}', i)) {
        flush();
        style = base;
        i += 3;
        continue;
      }
      var matched = false;
      for (final entry in _openToClose.entries) {
        final open = entry.key;
        if (text.startsWith(open, i)) {
          final close = text.indexOf(entry.value, i + open.length);
          if (close > i) {
            flush();
            final inner = text.substring(i + open.length, close);
            spans.add(TextSpan(text: inner, style: _apply(style, open)));
            i = close + entry.value.length;
            matched = true;
            break;
          }
        }
      }
      if (matched) continue;
      buf.write(text[i]);
      i++;
    }
    flush();
    if (spans.isEmpty) spans.add(TextSpan(text: text, style: base));
    return spans;
  }

  static TextStyle _apply(TextStyle base, String marker) {
    switch (marker) {
      case '**':
        return base.copyWith(fontWeight: FontWeight.w700);
      case '__':
        return base.copyWith(decoration: TextDecoration.underline);
      case '~~':
        return base.copyWith(decoration: TextDecoration.lineThrough);
      case '_':
        return base.copyWith(fontStyle: FontStyle.italic);
      default:
        return base;
    }
  }

  /// Wraps [selection] in the given marker pair; returns the new text and
  /// where the caret should land.
  static (String, TextSelection) wrap(
    String text,
    TextSelection sel,
    String open,
    String close,
  ) {
    if (!sel.isValid || sel.isCollapsed) return (text, sel);
    final before = text.substring(0, sel.start);
    final middle = text.substring(sel.start, sel.end);
    final after = text.substring(sel.end);
    final newText = '$before$open$middle$close$after';
    return (
      newText,
      TextSelection(
        baseOffset: sel.start + open.length,
        extentOffset: sel.start + open.length + middle.length,
      ),
    );
  }

  /// Paints `line 3` and line names ("lucid", "午餐") as chips: a tinted
  /// background plus the answer colour, so a reference never reads as prose.
  static List<InlineSpan> withReferences(
    List<TextSpan> spans,
    TextStyle base, {
    required Set<String> labels,
    required bool dark,
  }) {
    if (labels.isEmpty) return spans;
    final pattern = RegExp(
      r'line\s+\d+|[A-Za-z_][A-Za-z0-9_]*|[\u4e00-\u9fff]+',
    );
    final out = <InlineSpan>[];

    for (final span in spans) {
      final text = span.text;
      if (text == null || text.isEmpty) {
        out.add(span);
        continue;
      }
      var last = 0;
      for (final m in pattern.allMatches(text)) {
        final word = m.group(0)!;
        // the first word of a line names it; it is not a reference
        final isOwnName = m.start == 0;
        final isRef =
            word.startsWith('line ') ||
            (!isOwnName && labels.contains(word.toLowerCase()));
        if (!isRef) continue;
        if (m.start > last) {
          out.add(
            TextSpan(text: text.substring(last, m.start), style: span.style),
          );
        }
        final tint = dark ? const Color(0xFFE8B75A) : const Color(0xFFA8442B);
        out.add(
          TextSpan(
            text: word,
            style: (span.style ?? base).copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
              backgroundColor: tint.withValues(alpha: 0.14),
            ),
          ),
        );
        last = m.end;
      }
      if (last < text.length) {
        out.add(TextSpan(text: text.substring(last), style: span.style));
      }
    }
    return out;
  }

  /// Every line that starts with `//` is a draft: nothing is calculated.
  static bool isDraft(String line) => line.trimLeft().startsWith('//');

  /// Renders one editor line while keeping an exact 1:1 character count with
  /// [line] so EditableText caret/selection offsets never drift or crash.
  static List<InlineSpan> editorSpans(
    String line,
    TextStyle base, {
    required Set<String> labels,
    required bool dark,
  }) {
    if (line.isEmpty) return [TextSpan(text: '', style: base)];
    final faintColor = dark ? const Color(0xFF8E8B84) : const Color(0xFF8A8578);
    final accentColor = dark ? const Color(0xFFE8B75A) : const Color(0xFFA8442B);

    if (isDraft(line)) {
      return [
        TextSpan(
          text: line,
          style: base.copyWith(
            color: faintColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      ];
    }

    // Section heading: `# Heading`
    final trimmedLeft = line.trimLeft();
    if (trimmedLeft.startsWith('# ')) {
      final hashIdx = line.indexOf('# ');
      return [
        if (hashIdx > 0) TextSpan(text: line.substring(0, hashIdx), style: base),
        TextSpan(
          text: '# ',
          style: base.copyWith(color: faintColor.withValues(alpha: 0.7)),
        ),
        TextSpan(
          text: line.substring(hashIdx + 2),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ),
      ];
    }

    // Folded summary projection row: `  ⋯  3 lines ...`
    if (trimmedLeft.startsWith('⋯')) {
      return [
        TextSpan(
          text: line,
          style: base.copyWith(color: faintColor),
        ),
      ];
    }

    // Preserve marker characters in faint ink so EditableText offsets match 1:1
    final syntaxStyle = base.copyWith(
      color: faintColor.withValues(alpha: 0.42),
    );
    final rawSpans = <TextSpan>[];
    var activeStyle = base;
    final buf = StringBuffer();
    var i = 0;

    void flush() {
      if (buf.isNotEmpty) {
        rawSpans.add(TextSpan(text: buf.toString(), style: activeStyle));
        buf.clear();
      }
    }

    while (i < line.length) {
      final colour = RegExp(r'^\{(' + colours.keys.join('|') + r')\}')
          .firstMatch(line.substring(i));
      if (colour != null) {
        flush();
        final token = colour[0]!;
        rawSpans.add(TextSpan(text: token, style: syntaxStyle));
        activeStyle = activeStyle.copyWith(color: colours[colour[1]]);
        i += token.length;
        continue;
      }
      if (line.startsWith('{/}', i)) {
        flush();
        rawSpans.add(TextSpan(text: '{/}', style: syntaxStyle));
        activeStyle = base;
        i += 3;
        continue;
      }
      var matched = false;
      for (final entry in _openToClose.entries) {
        final open = entry.key;
        if (line.startsWith(open, i)) {
          final close = line.indexOf(entry.value, i + open.length);
          if (close > i) {
            flush();
            final inner = line.substring(i + open.length, close);
            rawSpans.add(TextSpan(text: open, style: syntaxStyle));
            rawSpans.add(TextSpan(text: inner, style: _apply(activeStyle, open)));
            rawSpans.add(TextSpan(text: entry.value, style: syntaxStyle));
            i = close + entry.value.length;
            matched = true;
            break;
          }
        }
      }
      if (matched) continue;
      buf.write(line[i]);
      i++;
    }
    flush();
    if (rawSpans.isEmpty) rawSpans.add(TextSpan(text: line, style: base));

    // Highlight trailing `#tag` and aggregate keywords
    final withTags = <TextSpan>[];
    final tagMatch = RegExp(r'(\s)(#[\w\u4e00-\u9fff]+)(\s*)$').firstMatch(line);
    if (tagMatch != null) {
      final tagStart = tagMatch.start + tagMatch.group(1)!.length;
      final tagEnd = tagStart + tagMatch.group(2)!.length;
      var offset = 0;
      for (final sp in rawSpans) {
        final t = sp.text ?? '';
        final spEnd = offset + t.length;
        if (spEnd <= tagStart || offset >= tagEnd) {
          withTags.add(sp);
        } else {
          if (tagStart > offset) {
            withTags.add(
              TextSpan(
                text: t.substring(0, tagStart - offset),
                style: sp.style,
              ),
            );
          }
          final s0 = (tagStart - offset).clamp(0, t.length);
          final s1 = (tagEnd - offset).clamp(0, t.length);
          withTags.add(
            TextSpan(
              text: t.substring(s0, s1),
              style: (sp.style ?? base).copyWith(
                color: accentColor,
                backgroundColor: accentColor.withValues(alpha: 0.10),
              ),
            ),
          );
          if (spEnd > tagEnd) {
            withTags.add(
              TextSpan(text: t.substring(tagEnd - offset), style: sp.style),
            );
          }
        }
        offset = spEnd;
      }
    } else {
      withTags.addAll(rawSpans);
    }

    // Highlight standalone aggregate lines (`sum`, `subtotal`, `小計`, `合共`)
    final cleanLower = stripMarkers(line).trim().toLowerCase();
    const aggSet = {
      'sum',
      'subtotal',
      'total',
      'average',
      'avg',
      'count',
      'min',
      'max',
      'grand total',
      '合共',
      '總共',
      '總計',
      '總和',
      '小計',
      '小计',
      '合计',
      '总共',
      '总计',
      '总和',
    };
    if (aggSet.contains(cleanLower) ||
        RegExp(r'^(?:total|sum|subtotal)\s+of\s+#').hasMatch(cleanLower)) {
      return [
        for (final sp in withTags)
          TextSpan(
            text: sp.text,
            style: (sp.style ?? base).copyWith(fontWeight: FontWeight.w600),
          ),
      ];
    }

    return withReferences(
      withTags,
      base,
      labels: labels.isEmpty && !line.contains('line ')
          ? const {}
          : (labels.isEmpty ? const {'__line_only__'} : labels),
      dark: dark,
    );
  }
}
