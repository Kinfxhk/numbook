import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../engine/values.dart';
import '../i18n/strings.dart';
import 'answer_column.dart';
import 'feedback.dart';
import 'marked_controller.dart';
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
  final room = math.max(0.0, width - gutter - padH * 2 - 200);
  final dragged = math.max(room, width - gutter - padH * 2 - 96);
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

double _gutterWidth(bool tight, double numberWidth) {
  final base = tight ? 32.0 : 54.0;
  if (numberWidth <= 0) return base;
  final slot = base - _foldSlot - _numberGap;
  if (numberWidth + _numberSlack <= slot) return base;
  return (_foldSlot + numberWidth + _numberGap + _numberSlack).ceilToDouble();
}

/// A single text field with answers aligned to each logical line.
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
  final FocusNode? focusNode;
  final ValueListenable<bool>? wheelBlocked;
  final Color? positiveColour;
  final Color? negativeColour;
  final NumberFormat numberFormat;
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

  /// Pure helper for scrubbing the number literal at [offset] by [stepDelta]
  /// units of its least-significant decimal place.
  static (String text, int selStart, int selEnd)? scrubNumberAt(
    String text,
    int offset,
    int stepDelta, {
    NumberFormat format = NumberFormat.us,
  }) {
    final tok = _findScrubToken(text, offset, format);
    if (tok == null) return null;
    final formatted = tok.formatStep(stepDelta, format);
    final out = '${tok.docPrefix}$formatted${tok.docSuffix}';
    return (out, tok.docPrefix.length, tok.docPrefix.length + formatted.length);
  }

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _ScrubToken {
  final String docPrefix;
  final String docSuffix;
  final double initialValue;
  final int decimals;
  final bool grouped;

  const _ScrubToken({
    required this.docPrefix,
    required this.docSuffix,
    required this.initialValue,
    required this.decimals,
    required this.grouped,
  });

  String formatStep(int stepDelta, NumberFormat format) {
    final unit = math.pow(10.0, -decimals).toDouble();
    final rawNext = initialValue + stepDelta * unit;
    final next = decimals == 0
        ? rawNext.roundToDouble()
        : double.parse(rawNext.toStringAsFixed(decimals));
    final cleanZero = next == 0 ? 0.0 : next;
    if (grouped) {
      return formatNumber(cleanZero, decimals: decimals, format: format);
    }
    return cleanZero
        .toStringAsFixed(decimals)
        .replaceAll('.', format.decimal);
  }
}

class _ScrubSession {
  final _ScrubToken token;
  final double startGlobalX;
  int lastSteps = 0;

  _ScrubSession({required this.token, required this.startGlobalX});
}

_ScrubToken? _findScrubToken(String text, int offset, NumberFormat format) {
  if (text.isEmpty) return null;
  final clamped = offset.clamp(0, text.length);
  final lineStart = clamped == 0 ? 0 : text.lastIndexOf('\n', clamped - 1) + 1;
  final nl = text.indexOf('\n', clamped);
  final lineEnd = nl < 0 ? text.length : nl;
  final line = text.substring(lineStart, lineEnd);
  if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('# ')) {
    return null;
  }
  final local = clamped - lineStart;
  final dec = RegExp.escape(format.decimal);
  final grp = RegExp.escape(format.group);
  final numRe = RegExp('(?<!\\w)-?\\d(?:[\\d$grp]*\\d)?(?:$dec\\d+)?');

  for (final m in numRe.allMatches(line)) {
    var s = m.start;
    final e = m.end;
    var raw = m.group(0)!;
    // Treat `-` as part of the number only when unary (not `100 - 20`)
    if (raw.startsWith('-') && s > 0) {
      final before = line.substring(0, s).trimRight();
      if (before.isNotEmpty) {
        final prevChar = before[before.length - 1];
        if (!r'(=:+*/^×÷,$€£¥₩₹฿'.contains(prevChar)) {
          s += 1;
          raw = raw.substring(1);
        }
      }
    }
    if (local >= s && local <= e) {
      final normalized = raw
          .replaceAll(format.group, '')
          .replaceAll(format.decimal, '.');
      final val = double.tryParse(normalized);
      if (val == null) return null;
      final decIdx = raw.indexOf(format.decimal);
      final decimals = decIdx < 0 ? 0 : raw.length - decIdx - 1;
      final grouped = raw.contains(format.group);
      return _ScrubToken(
        docPrefix: text.substring(0, lineStart + s),
        docSuffix: text.substring(lineStart + e),
        initialValue: val,
        decimals: decimals,
        grouped: grouped,
      );
    }
  }
  return null;
}

class _EditorViewState extends State<EditorView> {
  final _scroll = ScrollController();
  FocusNode? _ownFocus;
  late final FocusNode _focus = widget.focusNode ?? (_ownFocus = FocusNode());

  List<double> _tops = const [];
  double _lastHeight = 0;
  _ScrubSession? _scrub;

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

  void _revealCaret() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus || !_scroll.hasClients) return;
      final sel = widget.controller.selection;
      if (!sel.isValid) return;
      final caret = sel.extentOffset.clamp(0, widget.controller.text.length);
      final line = '\n'
          .allMatches(widget.controller.text.substring(0, caret))
          .length;
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

  /// Active caret line index when focused, or null when unfocused/readOnly.
  int? _activeLine() {
    if (!_focus.hasFocus || widget.readOnly) return null;
    final sel = widget.controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final caret = sel.extentOffset.clamp(0, widget.controller.text.length);
    return '\n'.allMatches(widget.controller.text.substring(0, caret)).length;
  }

  /// Current word or `#tag` prefix before the collapsed caret, plus its
  /// matching live completion items.
  (String prefix, List<CompletionItem> items) _currentCompletions() {
    if (!_focus.hasFocus || widget.readOnly) return ('', const []);
    final val = widget.controller.value;
    if (!val.selection.isValid || !val.selection.isCollapsed) {
      return ('', const []);
    }
    if (val.composing.isValid && !val.composing.isCollapsed) {
      return ('', const []);
    }
    final text = val.text;
    final caret = val.selection.extentOffset.clamp(0, text.length);
    // Only complete at the end of an identifier/tag token
    if (caret < text.length &&
        RegExp(r'[A-Za-z0-9_\u4e00-\u9fff]').hasMatch(text[caret])) {
      return ('', const []);
    }
    final before = text.substring(0, caret);
    final lineIdx = '\n'.allMatches(before).length;
    final lineStart = before.lastIndexOf('\n') + 1;
    final linePrefix = before.substring(lineStart);
    // Do not suggest variables when naming an assignment (`rent = ...` left side)
    if (!linePrefix.contains('=') &&
        !linePrefix.contains('+') &&
        !linePrefix.contains('-') &&
        !linePrefix.contains('*') &&
        !linePrefix.contains('/') &&
        !linePrefix.contains('(') &&
        linePrefix.trim().split(RegExp(r'\s+')).length <= 1 &&
        !linePrefix.trimLeft().startsWith('#')) {
      // Allow completing standalone aggregate keywords (`sub` -> `subtotal`)
      // and variables on a fresh expression line (`ren` -> `rent`).
    }
    final m = RegExp(
      r'(#[A-Za-z0-9_\u4e00-\u9fff]*|[A-Za-z\u4e00-\u9fff][A-Za-z0-9_\u4e00-\u9fff]*)$',
    ).firstMatch(linePrefix);
    if (m == null) return ('', const []);
    final prefix = m.group(1)!;
    final items = SheetEngine.completionsFor(widget.results, lineIdx, prefix);
    return (prefix, items);
  }

  void _applyCompletion(String prefix, CompletionItem item) {
    final c = widget.controller;
    if (c is MarkedController) {
      c.replacePrefixAtCaret(prefix.length, item.insertText);
    } else {
      final caret = c.selection.extentOffset.clamp(0, c.text.length);
      final start = (caret - prefix.length).clamp(0, caret);
      final next = c.text.replaceRange(start, caret, item.insertText);
      c.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(
          offset: start + item.insertText.length,
        ),
      );
    }
    tapFeedback(light: true);
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
        // Never mount a 16px step chevron inside a 0-width phone gutter, and
        // do not reserve 30px when steps are disabled.
        final stepGutter =
            (!widget.showSteps || widget.explain == null || m.tight)
            ? 0.0
            : 30.0;
        final gutterW = m.gutter;
        final answerW = m.answerW;
        if (_lastHeight != constraints.maxHeight) {
          _lastHeight = constraints.maxHeight;
          WidgetsBinding.instance.addPostFrameCallback((_) => _revealCaret());
        }
        final text = widget.controller.text;
        final textWidth = constraints.maxWidth - answerW - gutterW - m.padH * 2;
        final tops = _lineTops(text, style, textWidth < 80 ? 80 : textWidth);
        _tops = tops;
        final activeLine = _activeLine();
        final (compPrefix, completions) = _currentCompletions();

        final painted = DefaultTextStyle.of(
          context,
        ).style.merge(answerStyle(widget.dark, scale: widget.scale));
        final metrics = measureAnswers(
          widget.results.map((r) => r.display).whereType<String>(),
          (s) =>
              measureAnswerText(s, painted, MediaQuery.textScalerOf(context)),
          decimal: widget.numberFormat.decimal,
          group: widget.numberFormat.group,
        );

        Widget textField = TextField(
          controller: widget.controller,
          focusNode: _focus,
          maxLines: null,
          style: style,
          strutStyle: StrutStyle(
            fontFamily: monoFamily,
            fontSize: 15 * widget.scale,
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
        );

        if (completions.isNotEmpty) {
          textField = CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.tab): () =>
                  _applyCompletion(compPrefix, completions.first),
            },
            child: textField,
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: DragTarget<int>(
                onAcceptWithDetails: (d) => widget.onInsertReference?.call(
                  d.data,
                  _tokenFor(d.data - 1),
                ),
                builder: (context, candidate, rejected) =>
                    SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(m.padH, 12, m.padH, 96),
                      child: Stack(
                        children: [
                          // Whisper-subtle active row band so the eye bridges
                          // expression -> answer across wide desktop monitors.
                          if (activeLine != null && activeLine < tops.length)
                            Positioned(
                              top: tops[activeLine],
                              left: 0,
                              right: 0,
                              height: 28 * widget.scale,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Palette.fg(widget.dark).withValues(
                                      alpha: widget.dark ? 0.045 : 0.032,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          if (widget.showLineNumbers)
                            for (var i = 0; i < widget.results.length; i++)
                              Positioned(
                                top: (tops.length > i ? tops[i] : 0) + 6,
                                left: 0,
                                width: gutterW - _numberGap,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _selectLine(i),
                                  onLongPress: () => _foldLine(i),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: _foldSlot,
                                        child: _foldArrow(i),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${i + 1}',
                                          key: ValueKey('gutter-${i + 1}'),
                                          textAlign: TextAlign.right,
                                          maxLines: 1,
                                          softWrap: false,
                                          style: _lineNumberFace.copyWith(
                                            color: Palette.faint(widget.dark)
                                                .withValues(
                                                  alpha: i == activeLine
                                                      ? 0.9
                                                      : 0.55,
                                                ),
                                            fontWeight: i == activeLine
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          Padding(
                            padding: EdgeInsets.only(
                              left: gutterW,
                              right: answerW,
                            ),
                            child: MouseRegion(
                              cursor: _scrub != null
                                  ? SystemMouseCursors.resizeLeftRight
                                  : MouseCursor.defer,
                              child: Listener(
                                behavior: HitTestBehavior.translucent,
                                onPointerDown: (e) => _onScrubDown(
                                  e,
                                  style,
                                  textWidth < 80 ? 80 : textWidth,
                                ),
                                onPointerMove: _onScrubMove,
                                onPointerUp: (_) => _endScrub(),
                                onPointerCancel: (_) => _endScrub(),
                                child: textField,
                              ),
                            ),
                          ),
                          if (widget.answersVisible && answerW > 0)
                            for (var i = 0; i < widget.results.length; i++)
                              if (widget.results[i].display != null ||
                                  widget.results[i].engineError)
                                Positioned(
                                  top: (tops.length > i ? tops[i] : 0),
                                  right: 0,
                                  // Stay inside answerW so FittedBox scales wide
                                  // dates/numbers cleanly without crossing the
                                  // vertical hairline divider onto the note.
                                  width: answerW,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (stepGutter > 0)
                                        SizedBox(
                                          width: stepGutter,
                                          height: 28,
                                          child:
                                              (!widget.results[i].engineError &&
                                                  _hasOperators(
                                                    widget.results[i].text,
                                                  ))
                                              ? _StepButton(
                                                  dark: widget.dark,
                                                  onTap: () => _openSteps(
                                                    widget.results[i].text,
                                                  ),
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
              ),
            ),
            if (completions.isNotEmpty)
              Positioned(
                left: m.padH + gutterW,
                right: m.padH,
                bottom: 10,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: _AutocompleteBar(
                    key: const ValueKey('autocomplete-bar'),
                    dark: widget.dark,
                    items: completions,
                    onPick: (item) => _applyCompletion(compPrefix, item),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Mirrors SheetEngine.explain: two or more operations is "complex".
  static bool _hasOperators(String line) =>
      RegExp(r'[+\-*/^%×÷＋－＊／％]|乘|除|加|減|减').allMatches(line).length >= 2;

  bool _canExplainLine(String line) {
    if (!widget.showSteps || widget.explain == null) return false;
    if (_hasOperators(line)) return true;
    return widget.explain!(line).isNotEmpty;
  }

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

  int _originalFor(int visibleIndex) => visibleIndex < widget.lineMap.length
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

  Widget _cell(int i, AnswerColumnMetrics metrics) {
    final r = widget.results[i];
    final painted = DefaultTextStyle.of(
      context,
    ).style.merge(answerStyle(widget.dark, scale: widget.scale));
    final style = painted.copyWith(
      color: _answerColour(r) ?? painted.color,
      fontWeight: r.isGrandTotal ? FontWeight.w600 : painted.fontWeight,
    );
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

    Widget readout = AnswerReadout(
      display: r.display!,
      style: style,
      metrics: metrics,
      decimal: widget.numberFormat.decimal,
      group: widget.numberFormat.group,
    );

    // Balance-sheet overline on section subtotals and grand totals. Using
    // DecoratedBox adds zero layout padding, preserving exact decimal alignment.
    if (r.isSummary) {
      readout = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Palette.hairline(widget.dark),
              width: r.isGrandTotal ? 1.5 : 1.0,
            ),
          ),
        ),
        child: readout,
      );
    }

    final cell = _answerGestures(
      index: i,
      line: r.text,
      display: r.display!,
      canExplain: _canExplainLine(r.text),
      child: readout,
    );

    if (widget.onInsertReference == null) return cell;
    return Draggable<int>(
      data: i + 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _dragChip(_tokenFor(i), r.display!),
      childWhenDragging: Opacity(opacity: 0.35, child: cell),
      child: cell,
    );
  }

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

  void _onScrubDown(PointerDownEvent e, TextStyle style, double maxWidth) {
    if (widget.readOnly || !HardwareKeyboard.instance.isAltPressed) return;
    final text = widget.controller.text;
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      strutStyle: StrutStyle(
        fontFamily: monoFamily,
        fontSize: 15 * widget.scale,
        height: 28 / 15,
        forceStrutHeight: true,
      ),
    )..layout(maxWidth: maxWidth);
    final pos = painter.getPositionForOffset(e.localPosition);
    painter.dispose();
    final tok = _findScrubToken(text, pos.offset, widget.numberFormat);
    if (tok == null) return;
    setState(() {
      _scrub = _ScrubSession(token: tok, startGlobalX: e.position.dx);
    });
  }

  void _onScrubMove(PointerMoveEvent e) {
    final s = _scrub;
    if (s == null) return;
    final rawSteps = ((e.position.dx - s.startGlobalX) / 6.0).round();
    final mult = HardwareKeyboard.instance.isShiftPressed ? 10 : 1;
    final steps = rawSteps * mult;
    if (steps == s.lastSteps) return;
    s.lastSteps = steps;
    final formatted = s.token.formatStep(steps, widget.numberFormat);
    final next = '${s.token.docPrefix}$formatted${s.token.docSuffix}';
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: s.token.docPrefix.length,
        extentOffset: s.token.docPrefix.length + formatted.length,
      ),
    );
    tapFeedback(light: true);
  }

  void _endScrub() {
    if (_scrub != null) setState(() => _scrub = null);
  }

  Widget _answerGestures({
    required int index,
    required String line,
    required String display,
    required bool canExplain,
    required Widget child,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: LocaleScope.t(
          context,
          canExplain ? 'answerHintSteps' : 'answerHintCopy',
        ),
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
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
        ),
      ),
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
    final locale = LocaleScope.of(context);
    final joined = steps.join('\n');
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
                  T.of(locale, 'stepsTitle'),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: Palette.faint(widget.dark),
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(joined, style: editStyle()),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _copy(joined);
                      },
                      child: Text(
                        T.of(locale, 'copy'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Palette.faint(widget.dark),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(
                        T.of(locale, 'close'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Palette.answer(widget.dark),
                        ),
                      ),
                    ),
                  ],
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
    painter.dispose();
    return tops;
  }
}

class _StepButton extends StatelessWidget {
  final bool dark;
  final VoidCallback onTap;

  const _StepButton({required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
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

class _AutocompleteBar extends StatelessWidget {
  final bool dark;
  final List<CompletionItem> items;
  final ValueChanged<CompletionItem> onPick;

  const _AutocompleteBar({
    super.key,
    required this.dark,
    required this.items,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 36),
        decoration: BoxDecoration(
          color: Palette.bg(dark),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Palette.hairline(dark)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    color: Palette.hairline(dark),
                  ),
                Pressable(
                  onTap: () => onPick(items[i]),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        items[i].token,
                        style: TextStyle(
                          fontFamily: monoFamily,
                          fontSize: 12.5,
                          fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                          color: Palette.answer(dark),
                        ),
                      ),
                      if (items[i].preview != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          items[i].preview!,
                          style: TextStyle(
                            fontFamily: monoFamily,
                            fontSize: 11.5,
                            color: Palette.faint(dark),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
