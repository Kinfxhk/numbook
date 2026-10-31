import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../i18n/strings.dart';
import '../engine/values.dart';
import 'answer_column.dart';
import 'feedback.dart';
import 'theme.dart';

/// How much room an editor gives its own chrome at a given pane width.
///
/// One pane's width decides the gutter, the side padding and the widest answer
/// column that still leaves the text 200px. The split's drag handle measures
/// with this too, so the rule and the handle's x cannot drift apart.
class EditorMetrics {
  /// One side of the horizontal padding.
  final double padH;

  /// Line-number / fold gutter.
  final double gutter;

  /// The answer column after clamping; 0 when answers are hidden.
  final double answerW;

  /// A phone-sized pane: thinner chrome, and no step chevron column.
  final bool tight;

  const EditorMetrics({
    required this.padH,
    required this.gutter,
    required this.answerW,
    required this.tight,
  });
}

EditorMetrics editorMetrics({
  required double width,
  required bool answersVisible,
  required double wanted,
}) {
  final tight = width < 560;
  final padH = tight ? 12.0 : 24.0;
  final gutter = tight ? 32.0 : 54.0;
  // The answer column shrinks before the text does: a phone still needs a
  // readable line, and a scaled-down number beats a two-word-wide column.
  final room = math.max(0.0, width - gutter - padH * 2 - 200);
  return EditorMetrics(
    padH: padH,
    gutter: gutter,
    answerW: answersVisible ? math.min(wanted, room) : 0.0,
    tight: tight,
  );
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

  /// visible index -> original line index (-1 for a fold summary line)
  final List<int> lineMap;
  final Set<int> foldable;
  final Set<int> folded;
  final void Function(int originalLine)? onToggleFold;
  final bool readOnly;
  final double scale;
  final bool showLineNumbers;

  /// True while Ctrl is held, so the wheel can zoom instead of scrolling.
  final ValueListenable<bool>? wheelBlocked;
  final Color? positiveColour;
  final Color? negativeColour;

  /// The sheet's number format. The column must split on the same mark it
  /// painted, or `1.234,56` aligns on the grouping dot.
  final NumberFormat numberFormat;

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
    this.lineMap = const [],
    this.foldable = const {},
    this.folded = const {},
    this.onToggleFold,
    this.readOnly = false,
    this.scale = 1,
    this.showLineNumbers = true,
    this.wheelBlocked,
    this.positiveColour,
    this.negativeColour,
    this.numberFormat = NumberFormat.us,
  });

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  final _scroll = ScrollController();
  final _focus = FocusNode();

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
    setState(() {});
    // the caret moved, or the field was just tapped: a phone keyboard covers
    // the bottom of the pane, so keep the line being typed above it
    _revealCaret();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
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
        final m = editorMetrics(
          width: constraints.maxWidth,
          answersVisible: widget.answersVisible,
          wanted: widget.answerWidth,
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
                      width: gutterW - 10,
                      child: Row(
                        children: [
                          SizedBox(width: 14, child: _foldArrow(i)),
                          Expanded(
                            child: Text(
                              '${i + 1}',
                              key: ValueKey('gutter-${i + 1}'),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: monoFamily,
                                fontSize: 11,
                                color: Palette.faint(widget.dark)
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ],
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
                      hintText: LocaleScope.t(context, 'editorHint'),
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
    final original = visibleIndex < widget.lineMap.length
        ? widget.lineMap[visibleIndex]
        : visibleIndex;
    if (widget.onToggleFold == null || !widget.foldable.contains(original)) {
      return const SizedBox.shrink();
    }
    final isFolded = widget.folded.contains(original);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onToggleFold!(original),
      child: Icon(
        isFolded ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_down,
        size: 14,
        color: Palette.faint(widget.dark).withValues(alpha: 0.8),
      ),
    );
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
    final cell = _tapForSteps(
      line: r.text,
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

  /// The whole answer cell is the tap target on phones — the chevron is a
  /// hint, not a 16px button.
  Widget _tapForSteps({
    required String line,
    required bool canExplain,
    required Widget child,
  }) {
    // when dragging is available the cell must stay hit-testable
    if (!canExplain) {
      return widget.onInsertReference == null
          ? IgnorePointer(child: child)
          : child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        tapFeedback();
        _openSteps(line);
      },
      child: child,
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
