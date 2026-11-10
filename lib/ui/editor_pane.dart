import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/document.dart';
import '../engine/engine.dart';
import '../engine/presentation.dart';
import '../engine/values.dart';
import '../i18n/strings.dart';
import 'answer_column.dart';
import 'editor_paper.dart';
import 'editor_view.dart';
import 'feedback.dart';
import 'folding.dart';
import 'formatting.dart';
import 'marked_controller.dart';
import 'theme.dart';

/// Everything one editor owns: its text, engine, answers, answer width, fold
/// state, selection and save debounce. Two panes therefore cannot leak a
/// number, a cursor or a pending save into each other.
///
/// [sheetId] is the sheet this pane shows, which is not always the store's
/// active sheet: the focused pane owns that, the other one keeps its own.
class PaneState extends ChangeNotifier {
  final DocumentStore store;
  final SheetEngine Function() makeEngine;
  final controller = MarkedController(dark: false);

  /// The editor's focus node lives here, not in the view: the app asks it
  /// whether a soft keyboard is up for this pane (the key bar, BACK).
  final focus = FocusNode(debugLabel: 'pane');

  late SheetEngine engine;
  String sheetId;
  List<LineResult> results = const [];
  double answerW;
  bool dirty = false;
  DateTime? lastSaved;
  DisplayPrecision displayPrecision = DisplayPrecision.auto;
  PaperStyle paperStyle = PaperStyle.plain;
  bool highlightCurrentLine = false;

  /// True while the answer divider is being dragged (skip width tween).
  bool widthDragging = false;

  /// True once the rule was dragged or auto-fitted: the width is then the
  /// user's, and may take room from the text (see editorMetrics).
  bool explicitW;

  /// non-null while a section is folded: the full document, set aside
  List<String>? _foldSource;
  Set<int> _foldedLines = {};
  List<int> _lineMap = const [];
  Timer? _saveTimer;
  bool _syncing = false;
  bool _binding = false;
  bool _bound = false;
  bool _disposed = false;

  PaneState({
    required this.store,
    required this.sheetId,
    required this.makeEngine,
    required this.answerW,
    this.explicitW = false,
  }) {
    engine = makeEngine();
    controller.addListener(_onText);
    focus.addListener(_notify);
  }

  bool get disposed => _disposed;
  Sheet? get sheet => store.sheets.where((s) => s.id == sheetId).firstOrNull;
  List<int> get lineMap => _lineMap;
  Set<int> get folded => _foldedLines;
  bool get readOnly => _foldSource != null;
  bool get hasSelection =>
      controller.selection.isValid && !controller.selection.isCollapsed;

  Set<int> get foldable {
    final src = _foldSource ?? controller.text.split('\n');
    return {
      for (var i = 0; i < src.length; i++)
        if (isHeading(src[i])) i,
    };
  }

  /// What the sheet actually contains: while a section is folded the editor
  /// shows a projection, so the saved text must come from the full source.
  String get contentToSave => _foldSource?.join('\n') ?? controller.text;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Show [id]; a pending debounce lands in the old sheet first.
  void load(String id) {
    final target = store.sheets.where((s) => s.id == id).firstOrNull;
    if (target == null || _binding) return;
    if (id == sheetId && _bound) return;
    _binding = true;
    try {
      flush();
      sheetId = id;
      _syncing = true;
      _foldSource = null;
      _foldedLines = {};
      _lineMap = const [];
      controller.text = target.content;
      _syncing = false;
      _bound = true;
      recalc();
    } finally {
      _binding = false;
    }
  }

  void rebuildEngine() {
    engine = makeEngine();
    recalc();
  }

  void setDisplayPrecision(DisplayPrecision precision) {
    if (displayPrecision == precision) return;
    displayPrecision = precision;
    recalc();
  }

  void setPaperAppearance({
    PaperStyle? style,
    bool? highlightLine,
  }) {
    var changed = false;
    if (style != null && paperStyle != style) {
      paperStyle = style;
      changed = true;
    }
    if (highlightLine != null && highlightCurrentLine != highlightLine) {
      highlightCurrentLine = highlightLine;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void setWidthDragging(bool dragging) {
    if (widthDragging == dragging) return;
    widthDragging = dragging;
    _notify();
  }

  void resetAnswerWidth({double defaultWidth = 212}) {
    answerW = defaultWidth;
    explicitW = false;
    widthDragging = false;
    _notify();
  }

  void recalc() {
    // markers are presentation only: the engine sees plain arithmetic
    final lines = controller.text
        .split('\n')
        .map(Fmt.stripMarkers)
        .toList(growable: false);
    results = presentResults(
      engine.evaluate(lines),
      displayPrecision,
      engine.format,
    );
    _notify();
  }

  /// Write a pending debounce now, into the sheet it was typed in: a kill, a
  /// hidden window or a sheet switch would otherwise drop it.
  void flush() {
    if (!(_saveTimer?.isActive ?? false)) return;
    _saveTimer!.cancel();
    _persist(contentToSave);
    dirty = false;
  }

  /// Ctrl+S: write now instead of waiting for the debounce.
  void saveNow() {
    _saveTimer?.cancel();
    _persist(contentToSave);
    dirty = false;
    lastSaved = DateTime.now();
    _notify();
  }

  void _persist(String content) {
    final s = sheet;
    if (s == null) return;
    final firstLine = content
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .replaceAll(RegExp(r'^#\s*'), '')
        .trim();
    store.update(
      s.id,
      content: content,
      title: s.customTitle
          ? null
          : (firstLine.length > 34 ? firstLine.substring(0, 34) : firstLine),
    );
  }

  void _onText() {
    if (_syncing) return;
    dirty = true;
    _saveTimer?.cancel();
    final content = contentToSave;
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      if (_disposed) return;
      _persist(content);
      dirty = false;
      lastSaved = DateTime.now();
      _notify();
    });
    recalc();
  }

  /// Dropping an answer appends a live reference; the engine keeps it fresh.
  void insertReference(int line, String token) {
    final base = controller.text;
    final sep = base.isEmpty || base.endsWith('\n') ? '' : '\n';
    final text = '$base$sep$token';
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// A double-tapped answer goes where the caret already is: on a phone the
  /// caret is mid-note, and appending would put the reference out of reach.
  void insertReferenceAtCaret(int line, String token) =>
      controller.insertAtCaret(token);

  void format(String open, String close) {
    if (!hasSelection) return;
    final (text, selection) = Fmt.wrap(controller.text, controller.selection, open, close);
    controller.value = TextEditingValue(text: text, selection: selection);
  }

  void setAnswerWidth(double w) {
    answerW = w;
    explicitW = true;
    _notify();
  }

  /// The stored width arrives after the pane exists: adopt it without
  /// pretending it was just dragged.
  void adoptWidth(double w, bool wasSet) {
    answerW = w;
    explicitW = wasSet;
    _notify();
  }

  /// The rule was grabbed: from here the width is the user's, not a default.
  void grabWidth() {
    if (explicitW) return;
    explicitW = true;
    _notify();
  }

  /// Fold or unfold the section that starts at [original].
  /// Folding swaps the visible text for a projection, so the editor is
  /// read-only until the section is opened again — nothing can be lost.
  void toggleFold(int original) => setFolds(
    _foldedLines.contains(original)
        ? (Set<int>.from(_foldedLines)..remove(original))
        : {..._foldedLines, original},
  );

  /// The chevron's long press: every section at once, toggling either way.
  void toggleAllFolds() => setFolds(_foldedLines.isEmpty ? foldable : {});

  void setFolds(Set<int> folded) {
    final source = _foldSource ?? controller.text.split('\n');

    if (folded.isEmpty) {
      controller.text = source.join('\n');
      _foldSource = null;
      _foldedLines = {};
      _lineMap = List<int>.generate(source.length, (i) => i);
      recalc();
      return;
    }

    final result = foldDocument(source, folded);
    _foldSource = source;
    _foldedLines = folded;
    _lineMap = result.map;
    controller.text = result.visibleLines.join('\n');
    recalc();
  }

  /// Each line only sees the names defined above it.
  void applyLabels() {
    final labelsByLine = <Set<String>>[];
    final seen = <String>{};
    for (final r in results) {
      labelsByLine.add(Set.of(seen));
      final label = r.display == null ? null : SheetEngine.labelOf(r.text);
      if (label != null) seen.add(label);
    }
    controller.labelsByLine = labelsByLine;
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_onText);
    focus.removeListener(_notify);
    flush();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }
}

/// One pane: an optional 26px title row, then the editor with its answers.
class EditorPane extends StatelessWidget {
  final PaneState pane;
  final bool dark;
  final bool focused;

  /// Split mode shows each pane's title and its sheet menu; single mode is
  /// today's editor with nothing above it.
  final bool showTitle;
  final String? otherSheetId;
  final bool answersVisible;
  final bool showSteps;
  final bool showLineNumbers;
  final bool signColours;
  final Color? positiveColour;
  final Color? negativeColour;
  final ValueListenable<bool>? wheelBlocked;
  final VoidCallback onFocus;
  final ValueChanged<String> onPickSheet;
  final ValueChanged<double> onAnswerWidth;

  /// Only the right pane offers "close split" in its menu.
  final VoidCallback? onUnsplit;
  final NumberFormat numberFormat;

  const EditorPane({
    super.key,
    required this.pane,
    required this.dark,
    required this.focused,
    required this.onFocus,
    required this.onPickSheet,
    required this.onAnswerWidth,
    this.showTitle = false,
    this.otherSheetId,
    this.answersVisible = true,
    this.showSteps = true,
    this.showLineNumbers = true,
    this.signColours = true,
    this.positiveColour,
    this.negativeColour,
    this.wheelBlocked,
    this.onUnsplit,
    this.numberFormat = NumberFormat.us,
  });

  @override
  Widget build(BuildContext context) {
    // the drag handle sits on the answer rule, which is drawn with these
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final hasAnswers = pane.results.any(
          (r) => r.display != null || r.engineError,
        );
        // Same width the editor measures, so the drag handle and the gutter
        // agree once two-digit numbers widen a phone's column.
        final numbered = showLineNumbers ? pane.results.length : 0;
        final numberWidth = numbered == 0
            ? 0.0
            : lineNumberWidth(context, numbered);
        // An empty note's column is narrower (see editorMetrics); tweening it
        // keeps the first answer from snapping the text sideways.
        final em = editorMetrics(
          width: constraints.maxWidth,
          answersVisible: answersVisible,
          wanted: pane.answerW,
          hasAnswers: hasAnswers,
          explicit: pane.explicitW,
          numberWidth: numberWidth,
        );
        final target = em.answerW;
        // a finger needs a 44dp handle; a mouse keeps the old 10dp feel
        final touch = switch (defaultTargetPlatform) {
          TargetPlatform.android || TargetPlatform.iOS => true,
          _ => false,
        };
        final hitW = touch ? 44.0 : 10.0;
        // On touch the band leans into the answers: centred on the rule it
        // would cover the last text column, and the caret took the gesture.
        final hairIn = touch ? hitW * 0.7 : hitW / 2;
        double measureFit() {
          final painted = DefaultTextStyle.of(context).style
              .merge(answerStyle(dark, scale: 1));
          final scaler = MediaQuery.textScalerOf(context);
          final stepGutter = em.tight ? 0.0 : 30.0;
          final displays =
              pane.results.map((r) => r.display).whereType<String>();
          final m = measureAnswers(
            displays,
            (s) => measureAnswerText(s, painted, scaler),
            decimal: numberFormat.decimal,
            group: numberFormat.group,
            capFracW: measureAnswerText(
              '${numberFormat.decimal}9999',
              painted,
              scaler,
            ),
          );
          return (m.totalW + stepGutter + 12).clamp(96.0, em.cap);
        }

        return TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: pane.widthDragging
              ? Duration.zero
              : const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          builder: (context, w, _) {
            final m = editorMetrics(
              width: constraints.maxWidth,
              answersVisible: answersVisible,
              wanted: w,
              explicit: pane.explicitW,
              numberWidth: numberWidth,
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: EditorView(
                    controller: pane.controller,
                    focusNode: pane.focus,
                    results: pane.results,
                    dark: dark,
                    answersVisible: answersVisible,
                    showSteps: showSteps,
                    explain: pane.engine.explain,
                    answerWidth: w,
                    explicit: pane.explicitW,
                    scale: 1,
                    wheelBlocked: wheelBlocked,
                    showLineNumbers: showLineNumbers,
                    onInsertReference: pane.insertReference,
                    onInsertReferenceAtCaret: pane.insertReferenceAtCaret,
                    onFoldAll: pane.toggleAllFolds,
                    lineMap: pane.lineMap,
                    foldable: pane.foldable,
                    folded: pane.folded,
                    onToggleFold: pane.toggleFold,
                    readOnly: pane.readOnly,
                    signColours: signColours,
                    positiveColour: positiveColour,
                    negativeColour: negativeColour,
                    numberFormat: numberFormat,
                    paperStyle: pane.paperStyle,
                    highlightCurrentLine: pane.highlightCurrentLine,
                  ),
                ),
                if (answersVisible)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: m.answerW + m.padH - hairIn,
                    width: hitW,
                    child: _AnswerDivider(
                      key: const ValueKey('answer-divider'),
                      pane: pane,
                      dark: dark,
                      touch: touch,
                      hairIn: hairIn,
                      cap: em.cap,
                      hasAnswers: hasAnswers,
                      shown: m.answerW,
                      onAnswerWidth: onAnswerWidth,
                      measureFit: measureFit,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );

    if (!showTitle) return body;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onFocus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleRow(context),
          Expanded(child: body),
        ],
      ),
    );
  }

  /// The sheet's name, a chevron with every sheet, and which pane has focus.
  Widget _titleRow(BuildContext context) {
    final locale = LocaleScope.of(context);
    final sheets = [
      for (final s in pane.store.sheets)
        if (s.id != otherSheetId) s,
    ]..sort((a, b) => b.updated.compareTo(a.updated));
    final s = pane.sheet;
    final title = s == null || s.title.isEmpty
        ? T.of(locale, 'untitled')
        : s.title;
    return Container(
      height: 26,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: focused ? Palette.hairline(dark) : null,
        border: Border(bottom: BorderSide(color: Palette.hairline(dark))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: focused ? Palette.fg(dark) : Palette.faint(dark),
              ),
            ),
          ),
          if (MediaQuery.sizeOf(context).width < 700)
            // a popup here is pinned to the touch point and clipped at the
            // screen edge; the sheet sits where the thumb already is
            Pressable(
              onTap: () => _pickSheet(context, sheets),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 14,
                color: Palette.faint(dark),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: T.of(locale, 'sheets'),
              padding: EdgeInsets.zero,
              iconSize: 14,
              onSelected: _picked,
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: _newSheet,
                  height: 34,
                  child: Text(T.of(locale, 'newSheet'), style: _itemStyle),
                ),
                const PopupMenuDivider(),
                for (final sheet in sheets)
                  PopupMenuItem(
                    value: sheet.id,
                    height: 34,
                    child: Text(
                      sheet.title.isEmpty
                          ? T.of(locale, 'untitled')
                          : sheet.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _itemStyle,
                    ),
                  ),
                if (onUnsplit != null) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _unsplit,
                    height: 34,
                    child: Text(T.of(locale, 'unsplit'), style: _itemStyle),
                  ),
                ],
              ],
              icon: Icon(
                Icons.keyboard_arrow_down,
                size: 14,
                color: Palette.faint(dark),
              ),
            ),
        ],
      ),
    );
  }

  void _picked(String v) {
    if (v == _newSheet) {
      pane.store.create();
    } else if (v == _unsplit) {
      onUnsplit?.call();
    } else {
      onPickSheet(v);
    }
  }

  /// The phone's answer to the popup: 48dp rows at the bottom of the screen.
  Future<void> _pickSheet(BuildContext context, List<Sheet> sheets) async {
    final locale = LocaleScope.of(context);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.bg(dark),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (value, label) in [
              (_newSheet, T.of(locale, 'newSheet')),
              for (final s in sheets)
                (s.id, s.title.isEmpty ? T.of(locale, 'untitled') : s.title),
              if (onUnsplit != null) (_unsplit, T.of(locale, 'unsplit')),
            ])
              Pressable(
                onTap: () => Navigator.pop(ctx, value),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _itemStyle,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) _picked(chosen);
  }

  static const _newSheet = '__new';
  static const _unsplit = '__off';
  TextStyle get _itemStyle =>
      TextStyle(fontSize: 13, color: Palette.fg(dark));
}

/// The draggable rule between text and answers. Its width is this pane's.
///
/// Opaque on purpose: under this strip is the editor's own text field, and a
/// translucent one hands the pointer to the caret's selection drag, which wins
/// the touch arena — the reason a thumb could never move this rule.
class _AnswerDivider extends StatefulWidget {
  final PaneState pane;
  final bool dark;
  final bool touch;

  /// The hairline's inset from the band's right edge: the band may lean into
  /// the answers while the rule stays exactly where it was drawn.
  final double hairIn;

  /// The widest the pane will draw the column: a drag stops here.
  final double cap;
  final bool hasAnswers;

  /// What the rule shows now. A drag starts from here, not from the stored
  /// width: on a phone the column is capped, and a stored 212 would pin it.
  final double shown;

  final ValueChanged<double> onAnswerWidth;
  final double Function() measureFit;

  const _AnswerDivider({
    super.key,
    required this.pane,
    required this.dark,
    required this.touch,
    required this.hairIn,
    required this.cap,
    required this.hasAnswers,
    required this.shown,
    required this.onAnswerWidth,
    required this.measureFit,
  });

  @override
  State<_AnswerDivider> createState() => _AnswerDividerState();
}

class _AnswerDividerState extends State<_AnswerDivider> {
  double _from = 0;
  double _base = 0;
  double _total = 0;
  double? _cancelRestore;
  bool? _cancelExplicit;
  bool _hover = false;

  static const _minReadable = 96.0;
  static const _nudge = 8.0;

  double get _minW => widget.hasAnswers ? _minReadable : _minReadable;

  void _begin(double x) {
    _cancelRestore = widget.shown;
    _cancelExplicit = widget.pane.explicitW;
    widget.pane.grabWidth();
    widget.pane.setWidthDragging(true);
    _from = x;
    _total = 0;
    _base = widget.shown;
  }

  void _drag(double x) {
    _total += x - _from;
    _from = x;
    final lo = math.min(_minW, _base);
    final hi = widget.cap < lo ? lo : widget.cap;
    widget.pane.setAnswerWidth((_base - _total).clamp(lo, hi));
  }

  void _end() {
    widget.pane.setWidthDragging(false);
    _cancelRestore = null;
    _cancelExplicit = null;
    widget.onAnswerWidth(widget.pane.answerW);
  }

  void _cancel() {
    final restore = _cancelRestore;
    final wasExplicit = _cancelExplicit;
    if (restore != null) {
      widget.pane.adoptWidth(restore, wasExplicit ?? false);
    }
    widget.pane.setWidthDragging(false);
    _cancelRestore = null;
    _cancelExplicit = null;
  }

  void _nudgeBy(double delta) {
    widget.pane.grabWidth();
    final lo = _minW;
    final hi = widget.cap < lo ? lo : widget.cap;
    widget.pane.setAnswerWidth((widget.shown + delta).clamp(lo, hi));
    widget.onAnswerWidth(widget.pane.answerW);
  }

  @override
  Widget build(BuildContext context) {
    final hairline = Palette.hairline(widget.dark);
    return FocusableActionDetector(
      actions: {
        _NudgeAnswerIntent: CallbackAction<_NudgeAnswerIntent>(
          onInvoke: (i) {
            _nudgeBy(i.delta);
            return null;
          },
        ),
        _ResetAnswerIntent: CallbackAction<_ResetAnswerIntent>(
          onInvoke: (_) {
            widget.pane.resetAnswerWidth();
            widget.onAnswerWidth(widget.pane.answerW);
            return null;
          },
        ),
        _FitAnswerIntent: CallbackAction<_FitAnswerIntent>(
          onInvoke: (_) {
            widget.pane.setAnswerWidth(widget.measureFit());
            widget.onAnswerWidth(widget.pane.answerW);
            return null;
          },
        ),
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _NudgeAnswerIntent(8),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NudgeAnswerIntent(-8),
        SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            _NudgeAnswerIntent(24),
        SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            _NudgeAnswerIntent(-24),
        SingleActivator(LogicalKeyboardKey.keyR): _ResetAnswerIntent(),
        SingleActivator(LogicalKeyboardKey.keyF): _FitAnswerIntent(),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Tooltip(
          message: LocaleScope.t(context, 'answerDividerHint'),
          waitDuration: const Duration(milliseconds: 500),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => _begin(d.globalPosition.dx),
            onHorizontalDragUpdate: (d) => _drag(d.globalPosition.dx),
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: _cancel,
            onLongPressStart: (d) => _begin(d.globalPosition.dx),
            onLongPressMoveUpdate: (d) => _drag(d.globalPosition.dx),
            onLongPressEnd: (_) => _end(),
            onLongPressCancel: _cancel,
            onDoubleTap: () {
              widget.pane.setAnswerWidth(widget.measureFit());
              _end();
            },
            child: Semantics(
              label: LocaleScope.t(context, 'answerDivider'),
              hint: LocaleScope.t(context, 'answerDividerHint'),
              slider: true,
              value: widget.shown.toStringAsFixed(0),
              increasedValue: (widget.shown + _nudge).toStringAsFixed(0),
              decreasedValue: (widget.shown - _nudge).toStringAsFixed(0),
              onIncrease: () => _nudgeBy(_nudge),
              onDecrease: () => _nudgeBy(-_nudge),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: widget.hairIn - 0.5,
                    width: _hover || widget.pane.widthDragging ? 2 : 1,
                    child: Container(
                      key: const ValueKey('answer-rule'),
                      width: _hover || widget.pane.widthDragging ? 2 : 1,
                      color: hairline,
                    ),
                  ),
                  if (widget.touch)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: widget.hairIn - 1,
                      width: 2,
                      child: ListenableBuilder(
                        listenable: widget.pane.focus,
                        builder: (context, _) => !widget.pane.focus.hasFocus
                            ? const SizedBox.shrink()
                            : Center(
                                child: Container(
                                  width: 2,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: hairline,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NudgeAnswerIntent extends Intent {
  final double delta;
  const _NudgeAnswerIntent(this.delta);
}

class _ResetAnswerIntent extends Intent {
  const _ResetAnswerIntent();
}

class _FitAnswerIntent extends Intent {
  const _FitAnswerIntent();
}
