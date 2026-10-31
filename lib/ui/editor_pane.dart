import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/document.dart';
import '../engine/engine.dart';
import '../i18n/strings.dart';
import 'editor_view.dart';
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

  void recalc() {
    // markers are presentation only: the engine sees plain arithmetic
    final lines = controller.text
        .split('\n')
        .map(Fmt.stripMarkers)
        .toList(growable: false);
    results = engine.evaluate(lines);
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

  void format(String open, String close) {
    if (!hasSelection) return;
    final (text, selection) = Fmt.wrap(controller.text, controller.selection, open, close);
    controller.value = TextEditingValue(text: text, selection: selection);
  }

  void setAnswerWidth(double w) {
    answerW = w;
    _notify();
  }

  /// Fold or unfold the section that starts at [original].
  /// Folding swaps the visible text for a projection, so the editor is
  /// read-only until the section is opened again — nothing can be lost.
  void toggleFold(int original) {
    final source = _foldSource ?? controller.text.split('\n');
    final folded = Set<int>.from(_foldedLines);
    if (!folded.remove(original)) folded.add(original);

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
  });

  @override
  Widget build(BuildContext context) {
    // the drag handle sits on the answer rule, which is drawn with these
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final hasAnswers = pane.results.any(
          (r) => r.display != null || r.engineError,
        );
        // An empty note's column is narrower (see editorMetrics); tweening it
        // keeps the first answer from snapping the text sideways.
        final target = editorMetrics(
          width: constraints.maxWidth,
          answersVisible: answersVisible,
          wanted: pane.answerW,
          hasAnswers: hasAnswers,
        ).answerW;
        // a finger needs a 44dp handle; a mouse keeps the old 10dp feel
        final hitW = switch (defaultTargetPlatform) {
          TargetPlatform.android || TargetPlatform.iOS => 44.0,
          _ => 10.0,
        };
        return TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          builder: (context, w, _) {
            final m = editorMetrics(
              width: constraints.maxWidth,
              answersVisible: answersVisible,
              wanted: w,
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
                    scale: 1,
                    wheelBlocked: wheelBlocked,
                    showLineNumbers: showLineNumbers,
                    onInsertReference: pane.insertReference,
                    lineMap: pane.lineMap,
                    foldable: pane.foldable,
                    folded: pane.folded,
                    onToggleFold: pane.toggleFold,
                    readOnly: pane.readOnly,
                    signColours: signColours,
                    positiveColour: positiveColour,
                    negativeColour: negativeColour,
                  ),
                ),
                if (answersVisible)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: m.answerW + m.padH - hitW / 2,
                    width: hitW,
                    child: _AnswerDivider(
                      key: const ValueKey('answer-divider'),
                      pane: pane,
                      dark: dark,
                      onAnswerWidth: onAnswerWidth,
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
          PopupMenuButton<String>(
            tooltip: T.of(locale, 'sheets'),
            padding: EdgeInsets.zero,
            iconSize: 14,
            onSelected: (v) {
              if (v == _newSheet) {
                pane.store.create();
              } else if (v == _unsplit) {
                onUnsplit?.call();
              } else {
                onPickSheet(v);
              }
            },
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

  static const _newSheet = '__new';
  static const _unsplit = '__off';
  TextStyle get _itemStyle =>
      TextStyle(fontSize: 13, color: Palette.fg(dark));
}

/// The draggable rule between text and answers. Its width is this pane's.
class _AnswerDivider extends StatelessWidget {
  final PaneState pane;
  final bool dark;
  final ValueChanged<double> onAnswerWidth;

  const _AnswerDivider({
    super.key,
    required this.pane,
    required this.dark,
    required this.onAnswerWidth,
  });

  int get _widest => pane.results
      .map((r) => r.display?.length ?? 0)
      .fold<int>(0, (a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) {
          final minW = (_widest * 9.2 + 60).clamp(140.0, 520.0);
          pane.setAnswerWidth((pane.answerW - d.delta.dx).clamp(minW, 520.0));
        },
        onHorizontalDragEnd: (_) => onAnswerWidth(pane.answerW),
        onDoubleTap: () {
          pane.setAnswerWidth((_widest * 9.2 + 44).clamp(140.0, 520.0));
          onAnswerWidth(pane.answerW);
        },
        child: Center(child: Container(width: 1, color: Palette.hairline(dark))),
      ),
    );
  }
}
