import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../i18n/strings.dart';
import '../engine/values.dart';
import 'answer_column.dart';
import 'feedback.dart';
import 'theme.dart';

/// Fold chevron column. The digits sit beside it, so a number is never
/// drawn underneath the arrow.
const _foldSlot = 14.0;

/// Space between the line number and the first glyph of the line.
const _numberGap = 10.0;

/// Spare pixel so a glyph that rounds up does not wrap onto a second line.
const _numberSlack = 1.0;

/// The face the gutter paints. Width measurement must use this same face.
const _lineNumberFace = TextStyle(fontFamily: monoFamily, fontSize: 11);

/// How much room an editor gives its own chrome at a given pane width.
///
/// One pane's width decides the side padding and the widest answer column
/// that still leaves the text 200px. The gutter starts from that same width,
/// then grows once the line numbers no longer fit beside the fold chevron.
/// The answer column gives up the extra room. The split's drag handle
/// measures with this too, so the rule and the handle's x cannot drift apart.
class EditorMetrics {
  /// One side of the horizontal padding.
  final double padH;

  /// Line-number / fold gutter.
  final double gutter;

  /// The answer column after clamping; 0 when answers are hidden.
  final double answerW;

  /// A phone-sized pane: thinner chrome, and no step chevron column.
  final bool tight;

  /// The widest this pane will draw the column: a drag clamps to it.
  final double cap;

  const EditorMetrics({
    required this.padH,
    required this.gutter,
    required this.answerW,
    required this.tight,
    required this.cap,
  });
}

/// Painted width of line number [lineCount], in the gutter's own face.
///
/// The test font and a phone's monospace are not the same width, so the
/// gutter asks the painter instead of assuming a digit is 7px.
double lineNumberWidth(BuildContext context, int lineCount) {
  final n = lineCount < 1 ? 1 : lineCount;
  final style = DefaultTextStyle.of(context).style.merge(_lineNumberFace);
  final painter = TextPainter(
    text: TextSpan(text: '$n', style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

EditorMetrics editorMetrics({
  required double width,
  required bool answersVisible,
  required double wanted,
  bool hasAnswers = true,
  bool explicit = false,
  double numberWidth = 0,
}) {
  final tight = width < 560;
  final padH = tight ? 12.0 : 24.0;
  final gutter = _gutterWidth(tight, numberWidth);
  // The answer column shrinks before the text does: a phone still needs a
  // readable line, and a scaled-down number beats a two-word-wide column.
  final room = math.max(0.0, width - gutter - padH * 2 - 200);
  // ...unless the user dragged the rule: then the line keeps 96dp and wraps,
  // which is what dragging a rule means. 200 is the default, not a limit.
  final dragged = math.max(room, width - gutter - padH * 2 - 96);
  // An empty note has nothing to align, so the column only keeps room for the
  // hint — a quarter of the pane at most.
  final cap = hasAnswers
      ? (explicit ? dragged : room)
      : math.min(room, width * 0.25);
  return EditorMetrics(
    padH: padH,
    gutter: gutter,
    answerW: answersVisible ? math.min(wanted, cap) : 0.0,
    tight: tight,
    cap: cap,
  );
}

/// Base gutter, widened when [numberWidth] does not fit in it.
///
/// A phone reserves 32. Fourteen of that is the fold chevron and ten is the
/// gap before the text, which leaves the digits 8px. A single figure fits.
/// "10" does not: it wraps, and the second digit drops onto the line below.
/// A desktop's 54 already holds several digits; it grows only when a note
/// is long enough to need it.
double _gutterWidth(bool tight, double numberWidth) {
  final base = tight ? 32.0 : 54.0;
  if (numberWidth <= 0) return base;
  final slot = base - _foldSlot - _numberGap;
  if (numberWidth + _numberSlack <= slot) return base;
  return (_foldSlot + numberWidth + _numberGap + _numberSlack).ceilToDouble();
}

/// A single text field with answers aligned to each logical line.
///
/// Answers are positioned with a TextPainter over the same text/style/width,
/// so soft-wrapped lines still line up without a per-line widget tree.
/// The answer column itself is measured in pixels ([AnswerReadout]) so the
/// decimal points share one x even when a glyph is not one digit wide.
class EditorView extends StatefulWidget {
  final TextEditingController controller;
  final List<LineResult> results;
  final bool dark;
  final bool answersVisible;
  final List<String> Function(String line)? explain;
  final bool showSteps;
  final double answerWidth;
  final ValueChanged<double>? onAnswerWidth;
  final bool signColours;
  final void Function(int line, String token)? onInsertReference;

  /// The double-tap path: a reference goes in at the caret, not at the end.
  final void Function(int line, String token)? onInsertReferenceAtCaret;
  final VoidCallback? onFoldAll;

  /// visible index -> original line index (-1 for a fold summary line)
  final List<int> lineMap;
  final Set<int> foldable;
  final Set<int> folded;
  final void Function(int originalLine)? onToggleFold;
  final bool readOnly;
  final double scale;
  final bool showLineNumbers;

  /// The pane owns the focus node (the key bar asks whether it has focus).
  /// Standalone use — a test harness — gets a node of its own.
  final FocusNode? focusNode;

  /// True while Ctrl is held, so the wheel can zoom instead of scrolling.
  final ValueListenable<bool>? wheelBlocked;
  final Color? positiveColour;
  final Color? negativeColour;

  /// The sheet's number format. The column must split on the same mark it
  /// painted, or `1.234,56` aligns on the grouping dot.
  final NumberFormat numberFormat;

  /// The user set this width by hand, so it may take room from the text.
  final bool explicit;

  const EditorView({
    super.key,
    required this.controller,
    required this.results,
    required this.dark,
    this.answersVisible = true,
    this.explain,
    this.showSteps = true,
    this.answerWidth = 212,
    this.onAnswerWidth,
    this.signColours = true,
    this.onInsertReference,
    this.onInsertReferenceAtCaret,
    this.onFoldAll,
    this.lineMap = const [],
    this.foldable = const {},
    this.folded = const {},
    this.onToggleFold,
    this.readOnly = false,
    this.scale = 1,
    this.showLineNumbers = true,
    this.focusNode,
    this.wheelBlocked,
    this.positiveColour,
    this.negativeColour,
    this.numberFormat = NumberFormat.us,
    this.explicit = false,
  });

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  final _scroll = ScrollController();

  /// Only ours to close when the pane did not hand one over.
  FocusNode? _ownFocus;
  late final FocusNode _focus = widget.focusNode ?? (_ownFocus = FocusNode());

  /// Line tops from the last build, so the caret can be scrolled into view.
  List<double> _tops = const [];
  double _lastHeight = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant EditorView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    // the caret moved, or the field was just tapped: a phone keyboard covers
    // the bottom of the pane, so keep the line being typed above it
    _revealCaret();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.removeListener(_onChanged);
    _ownFocus?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Scroll the pane so the caret's line is inside it. Only the focused pane
  /// does this, so the other sheet keeps the scroll position it had.
  void _revealCaret() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus || !_scroll.hasClients) return;
      final sel = widget.controller.selection;
      if (!sel.isValid) return;
      final caret = sel.extentOffset.clamp(0, widget.controller.text.length);
      final line = '\n'.allMatches(widget.controller.text.substring(0, caret)).length;
      if (line >= _tops.length) return;
      final top = _tops[line];
      final pos = _scroll.position;
      final view = pos.viewportDimension;
      const lineH = 28.0;
      final low = pos.pixels + 8;
      final high = pos.pixels + view - lineH - 8;
      if (top >= low && top <= high) return;
      final target = top < low ? top - 8 : top + lineH - view + 8;
      _scroll.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = editorStyle(widget.dark, scale: widget.scale);

    return LayoutBuilder(
      builder: (context, constraints) {
        final numbered = widget.showLineNumbers ? widget.results.length : 0;
        final m = editorMetrics(
          width: constraints.maxWidth,
          answersVisible: widget.answersVisible,
          wanted: widget.answerWidth,
          explicit: widget.explicit,
          numberWidth: numbered == 0 ? 0.0 : lineNumberWidth(context, numbered),
        );
        final stepGutter = m.tight ? 0.0 : 30.0; // finger-sized on a desktop
        final gutterW = m.gutter;
        final answerW = m.answerW;
        // the keyboard opening changes the height, not the caret: give the
        // line being typed a nudge into view when the room shrinks
        if (_lastHeight != constraints.maxHeight) {
          _lastHeight = constraints.maxHeight;
          WidgetsBinding.instance.addPostFrameCallback((_) => _revealCaret());
        }
        final text = widget.controller.text;
        final textWidth = constraints.maxWidth - answerW - gutterW - m.padH * 2;
        final tops = _lineTops(text, style, textWidth < 80 ? 80 : textWidth);
        _tops = tops;
        // Text merges the ambient style at paint time. Measure that same
        // face, or a theme letter-spacing shows up only in the glyphs and
        // the row overflows by a fraction of a character.
        final painted = DefaultTextStyle.of(context).style
            .merge(answerStyle(widget.dark, scale: widget.scale));
        final metrics = measureAnswers(
          widget.results.map((r) => r.display).whereType<String>(),
          (s) =>
              measureAnswerText(s, painted, MediaQuery.textScalerOf(context)),
          decimal: widget.numberFormat.decimal,
          group: widget.numberFormat.group,
        );

        return DragTarget<int>(
          onAcceptWithDetails: (d) =>
              widget.onInsertReference?.call(d.data, _tokenFor(d.data - 1)),
          builder: (context, candidate, rejected) => SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(m.padH, 12, m.padH, 96),
            child: Stack(
              children: [
                // faint line numbers, aligned with the same text metrics
                if (widget.showLineNumbers)
                  for (var i = 0; i < widget.results.length; i++)
                    Positioned(
                      top: (tops.length > i ? tops[i] : 0) + 6,
                      left: 0,
                      width: gutterW - _numberGap,
                      // tap picks the whole line, a long press folds it —
                      // the same verb as the chevron, on the number
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selectLine(i),
                        onLongPress: () => _foldLine(i),
                        child: Row(
                          children: [
                            SizedBox(width: _foldSlot, child: _foldArrow(i)),
                            Expanded(
                              child: Text(
                                '${i + 1}',
                                key: ValueKey('gutter-${i + 1}'),
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                softWrap: false,
                                style: _lineNumberFace.copyWith(
                                  color: Palette.faint(widget.dark)
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                Padding(
                  padding: EdgeInsets.only(left: gutterW, right: answerW),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    maxLines: null,
                    style: style,
                    strutStyle: StrutStyle(
                      fontFamily: monoFamily,
                      fontSize: 15,
                      height: 28 / 15,
                      forceStrutHeight: true,
                    ),
                    readOnly: widget.readOnly,
                    cursorColor: Palette.answer(widget.dark),
                    cursorWidth: 1.6,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: LocaleScope.t(
                        context,
                        m.tight ? 'editorHintShort' : 'editorHint',
                      ),
                    ),
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
                if (widget.answersVisible)
                  for (var i = 0; i < widget.results.length; i++)
                    if (widget.results[i].display != null ||
                        widget.results[i].engineError)
                      Positioned(
                        top: (tops.length > i ? tops[i] : 0),
                        right: 0,
                        // never clip: the decimal grid needs its full width
                        width: answerW < metrics.totalW + stepGutter
                            ? metrics.totalW + stepGutter
                            : answerW,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // the step marker lives in its own gutter so numbers
                            // never move because of it
                            SizedBox(
                              width: stepGutter,
                              height: 28,
                              child:
                                  (widget.showSteps &&
                                      widget.explain != null &&
                                      !widget.results[i].engineError &&
                                      _hasOperators(widget.results[i].text))
                                  ? _StepButton(
                                      dark: widget.dark,
                                      onTap: () =>
                                          _openSteps(widget.results[i].text),
                                    )
                                  : null,
                            ),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: _cell(i, metrics),
                              ),
                            ),
                          ],
                        ),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Mirrors SheetEngine.explain: two or more operations is "complex".
  /// Fullwidth operators count too; the engine folds them before parsing,
  /// but the raw line still has the glyphs the user typed.
  static bool _hasOperators(String line) =>
      RegExp(r'[+\-*/^%×÷＋－＊／％]|乘|除|加|減|减').allMatches(line).length >= 2;

  Widget _foldArrow(int visibleIndex) {
    final original = _originalFor(visibleIndex);
    if (widget.onToggleFold == null || !widget.foldable.contains(original)) {
      return const SizedBox.shrink();
    }
    final isFolded = widget.folded.contains(original);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        tapFeedback();
        widget.onToggleFold!(original);
      },
      // one gesture for the whole document, toggling both ways
      onLongPress: widget.onFoldAll == null
          ? null
          : () {
              tapFeedback(light: true);
              widget.onFoldAll!();
            },
      child: Icon(
        isFolded ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_down,
        size: 14,
        color: Palette.faint(widget.dark).withValues(alpha: 0.8),
      ),
    );
  }

  int _originalFor(int visibleIndex) =>
      visibleIndex < widget.lineMap.length
      ? widget.lineMap[visibleIndex]
      : visibleIndex;

  void _foldLine(int visibleIndex) {
    final original = _originalFor(visibleIndex);
    if (widget.onToggleFold == null || !widget.foldable.contains(original)) {
      return;
    }
    tapFeedback();
    widget.onToggleFold!(original);
  }

  /// The gutter's tap: the whole logical line the number sits beside.
  void _selectLine(int visibleIndex) {
    final text = widget.controller.text;
    var start = 0;
    for (var i = 0; i < visibleIndex; i++) {
      final nl = text.indexOf('\n', start);
      if (nl < 0) return;
      start = nl + 1;
    }
    final nl = text.indexOf('\n', start);
    widget.controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: nl < 0 ? text.length : nl,
    );
    _focus.requestFocus();
    tapFeedback();
  }

  /// One answer cell, with drag-to-reference when the sheet supports it.
  Widget _cell(int i, AnswerColumnMetrics metrics) {
    final r = widget.results[i];
    final painted = DefaultTextStyle.of(context).style
        .merge(answerStyle(widget.dark, scale: widget.scale));
    final style = painted.copyWith(color: _answerColour(r) ?? painted.color);
    // A real error is this line's answer: say so where the number would be.
    if (r.engineError) {
      return Text(
        r.error!,
        key: ValueKey('engine-error-$i'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: style.copyWith(fontStyle: FontStyle.italic),
      );
    }
    final cell = _answerGestures(
      index: i,
      line: r.text,
      display: r.display!,
      canExplain:
          widget.showSteps && widget.explain != null && _hasOperators(r.text),
      child: AnswerReadout(
        display: r.display!,
        style: style,
        metrics: metrics,
        decimal: widget.numberFormat.decimal,
        group: widget.numberFormat.group,
      ),
    );

    if (widget.onInsertReference == null) return cell;
    // Draggable (not LongPress) keeps a plain tap free for the steps dialog
    return Draggable<int>(
      data: i + 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _dragChip(_tokenFor(i), r.display!),
      childWhenDragging: Opacity(opacity: 0.35, child: cell),
      child: cell,
    );
  }

  /// A line's own word if it has one, otherwise its number.
  String _tokenFor(int i) =>
      SheetEngine.labelOf(widget.results[i].text) ?? 'line ${i + 1}';

  Widget _dragChip(String token, String value) => Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Palette.bg(widget.dark),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Palette.answer(widget.dark)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$token  ·  $value',
        style: TextStyle(
          fontFamily: monoFamily,
          fontSize: 13,
          color: Palette.fg(widget.dark),
        ),
      ),
    ),
  );

  /// Negative in red, positive in green — both overridable in Settings.
  Color? _answerColour(LineResult r) {
    if (r.error != null) {
      return Palette.answer(widget.dark).withValues(alpha: 0.6);
    }
    if (!widget.signColours) return null;
    final v = r.value;
    final n = switch (v) {
      NumValue(:final value) => value,
      MoneyValue(:final value) => value,
      PercentValue(:final ratio) => ratio,
      _ => null,
    };
    if (n == null || n == 0) return null;
    return n < 0
        ? (widget.negativeColour ?? Palette.negative(widget.dark))
        : (widget.positiveColour ?? Palette.positive(widget.dark));
  }

  /// Tap expands the steps; a long press (or a desktop right-click) copies
  /// the number, which is the thing people actually want off a phone.
  /// A double tap drops a reference into the caret — the mouse's drag, for
  /// a finger that cannot drag and type at once.
  /// The whole cell is the target — the chevron is a hint, not a 16px button.
  Widget _answerGestures({
    required int index,
    required String line,
    required String display,
    required bool canExplain,
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canExplain
          ? () {
              tapFeedback();
              _openSteps(line);
            }
          : null,
      onLongPress: () => _copy(display),
      onSecondaryTap: () => _copy(display),
      onDoubleTap: widget.onInsertReferenceAtCaret == null
          ? null
          : () {
              tapFeedback(light: true);
              widget.onInsertReferenceAtCaret!(index + 1, _tokenFor(index));
            },
      child: child,
    );
  }

  void _copy(String display) {
    Clipboard.setData(ClipboardData(text: display));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(LocaleScope.t(context, 'copied')),
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  Future<void> _openSteps(String line) async {
    final steps = widget.explain!(line);
    if (!mounted) return;
    if (steps.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Palette.bg(widget.dark),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Steps',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: Palette.faint(widget.dark),
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(steps.join('\n'), style: editStyle()),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 13,
                        color: Palette.answer(widget.dark),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle editStyle() => TextStyle(
    fontFamily: monoFamily,
    fontSize: 13.5,
    height: 1.7,
    color: Palette.fg(widget.dark),
  );

  /// Vertical offset of each logical line, honouring soft wraps.
  List<double> _lineTops(String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      strutStyle: StrutStyle(
        fontFamily: monoFamily,
        fontSize: 15 * widget.scale,
        height: 28 / 15,
        forceStrutHeight: true,
      ),
    )..layout(maxWidth: width);

    final tops = <double>[];
    var offset = 0;
    for (final line in text.split('\n')) {
      final caret = painter.getOffsetForCaret(
        TextPosition(offset: offset),
        Rect.zero,
      );
      tops.add(caret.dy);
      offset += line.length + 1;
    }
    return tops;
  }
}

class _StepButton extends StatelessWidget {
  final bool dark;
  final VoidCallback onTap;

  const _StepButton({required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // the whole gutter cell is tappable; only the glyph is small
    return Semantics(
      button: true,
      label: LocaleScope.t(context, 'showSteps'),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.expand(
          child: Icon(
            Icons.chevron_right,
            size: 16,
            color: Palette.faint(dark),
          ),
        ),
      ),
    );
  }
}
