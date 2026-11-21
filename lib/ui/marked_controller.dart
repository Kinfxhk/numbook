import 'package:material_ui/material_ui.dart';

import 'formatting.dart';

/// Renders the inline markers (**bold**, _italic_, ~~strike~~, __underline__,
/// {red}colour{/}) without turning the sheet into a rich-text document.
class MarkedController extends TextEditingController {
  bool dark;

  /// For each line, the names of the lines *above* it. Only those are live
  /// references; a line's own name is just a name.
  List<Set<String>> labelsByLine = const [];
  MarkedController({super.text, required this.dark});

  /// Put [s] where the caret is (replacing a selection), as the key bar's
  /// chips do: a phone's IME never sees these keys, so they land as typed.
  void insertAtCaret(String s) {
    final v = value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: text.length);
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    final next = text.replaceRange(start, end, s);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + s.length),
    );
  }

  /// Replaces [prefixLen] characters right before the collapsed caret with
  /// [replacement], used by inline variable and `#tag` completion.
  void replacePrefixAtCaret(int prefixLen, String replacement) {
    final v = value;
    final caret = (v.selection.isValid ? v.selection.extentOffset : text.length)
        .clamp(0, text.length);
    final start = (caret - prefixLen).clamp(0, caret);
    final next = text.replaceRange(start, caret, replacement);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  /// Delete the selection, or the character before the caret.
  void deleteBack() {
    final v = value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: text.length);
    var start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    if (start == end) {
      if (start == 0) return;
      start -= 1;
    }
    final next = text.replaceRange(start, end, '');
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final children = <InlineSpan>[];
    final lines = text.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      children.addAll(
        Fmt.editorSpans(
          line,
          base,
          labels: i < labelsByLine.length ? labelsByLine[i] : const {},
          dark: dark,
        ),
      );
      if (i < lines.length - 1) children.add(TextSpan(text: '\n', style: base));
    }

    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      // keep the IME's composing range visible while typing Chinese
      final start = value.composing.start.clamp(0, text.length);
      final end = value.composing.end.clamp(0, text.length);
      return TextSpan(
        style: base,
        children: [
          ...children.take(0),
          TextSpan(text: text.substring(0, start), style: base),
          TextSpan(
            text: text.substring(start, end),
            style: base.copyWith(decoration: TextDecoration.underline),
          ),
          TextSpan(text: text.substring(end), style: base),
        ],
      );
    }

    return TextSpan(style: base, children: children);
  }
}
