import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/strings.dart';
import 'io/document_io.dart';
import 'io/file_actions.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/document.dart';
import 'data/rates.dart';
import 'engine/engine.dart';
import 'engine/values.dart';
import 'ui/editor_pane.dart';
import 'ui/feedback.dart';
import 'ui/formatting.dart';
import 'ui/settings_sheet.dart';
import 'ui/sidebar.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TallynoteApp());
}

class TallynoteApp extends StatefulWidget {
  const TallynoteApp({super.key});

  @override
  State<TallynoteApp> createState() => _AppState();
}

class _AppState extends State<TallynoteApp> with WidgetsBindingObserver {
  final _store = DocumentStore();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _navKey = GlobalKey<NavigatorState>();

  late PaneState _paneA;

  /// Non-null while the split is on: the second editor.
  PaneState? _paneB;
  bool _focusB = false;

  /// Set while the app itself adds the split's second sheet: that store
  /// notification must not move the new sheet into the first pane too.
  bool _routingOwn = false;

  bool _dark = false;
  bool _sidebarOpen = true;
  bool _answersVisible = true;
  bool _autoRates = true;
  bool _steps = true;

  /// The stored default answer width; each pane keeps its own once dragged.
  double _answerW = 212;
  double _uiScale = 1.0;
  String? _locale; // null = follow the system
  String _numberPreset = 'us';
  bool _lineNumbers = true;
  bool _showTabs = true;
  final List<String> _tabs = [];

  /// Ctrl/Cmd held: the wheel zooms instead of scrolling.
  final ValueNotifier<bool> _zoomModifier = ValueNotifier(false);
  bool _zoomHud = false;
  bool _savedFlash = false;
  final FocusNode _searchFocus = FocusNode();
  Timer? _zoomHudTimer;

  bool get _split => _paneB != null;

  /// The pane that takes a sidebar click, a new sheet and the shortcuts.
  PaneState get _focused => (_focusB && _paneB != null) ? _paneB! : _paneA;

  List<PaneState> get _livePanes => [_paneA, ?_paneB];

  bool _onKey(KeyEvent e) {
    final down =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (_zoomModifier.value != down) _zoomModifier.value = down;
    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_zoomModifier.value) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _zoom(dy < 0 ? 1.1 : 1 / 1.1);
    });
  }

  bool _signColours = true;
  String _posName = ''; // empty = the built-in paper-and-ink colours
  String _negName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _paneA = _newPane('');
    unawaited(_boot());
  }

  PaneState _newPane(String sheetId) {
    final pane = PaneState(
      store: _store,
      sheetId: sheetId,
      makeEngine: _makeEngine,
      answerW: _answerW,
    )..addListener(_onPane);
    // an empty id means "not bound yet": _boot loads the active sheet into it
    pane.load(sheetId);
    return pane;
  }

  void _onPane() {
    if (mounted) setState(() {});
  }

  SheetEngine _makeEngine() => SheetEngine(
    rates: Rates.current,
    format: NumberFormat.ofPreset(_numberPreset),
  );

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    _dark = prefs.getBool('tallynote.dark') ?? false;
    _answersVisible = prefs.getBool('tallynote.answers') ?? true;
    _autoRates = prefs.getBool('tallynote.autoRates') ?? true;
    _steps = prefs.getBool('tallynote.steps') ?? true;
    _answerW = prefs.getDouble('tallynote.answerWidth') ?? 212;
    _uiScale = prefs.getDouble('tallynote.uiScale') ?? 1.0;
    _locale = prefs.getString('tallynote.locale');
    _numberPreset = prefs.getString('tallynote.numberFormat') ?? 'us';
    _lineNumbers = prefs.getBool('tallynote.lineNumbers') ?? true;
    _showTabs = prefs.getBool('tallynote.showTabs') ?? true;
    _signColours = prefs.getBool('tallynote.signColours') ?? true;
    _posName = prefs.getString('tallynote.posColour') ?? '';
    _negName = prefs.getString('tallynote.negColour') ?? '';
    final splitOn = prefs.getBool('tallynote.split') ?? false;
    final splitSheet = prefs.getString('tallynote.splitSheet') ?? '';
    final splitFirst = prefs.getString('tallynote.splitPrimary') ?? '';

    await _store.load();
    _store.addListener(_onStore);
    // the left pane keeps its own sheet, so a restart does not swap the sides
    final first =
        splitOn &&
            splitFirst != splitSheet &&
            _store.sheets.any((s) => s.id == splitFirst)
        ? splitFirst
        : _store.activeId!;
    _paneA.load(first);
    if (splitOn) _restoreSplit(splitSheet);
    _focusB = _paneB != null && _store.activeId == _paneB!.sheetId;
    await Rates.load(allowNetwork: _autoRates);
    for (final p in _livePanes) {
      p.rebuildEngine();
    }
    if (!mounted) return;
    setState(() {});
  }

  /// The first pane shows the active sheet, the second the stored one.
  void _restoreSplit(String stored) {
    final active = _paneA.sheetId;
    if (_store.sheets.length < 2) return;
    final known =
        stored.isNotEmpty &&
        stored != active &&
        _store.sheets.any((s) => s.id == stored);
    final second = known
        ? stored
        : _store.sheets.firstWhere((s) => s.id != active).id;
    _paneB = _newPane(second);
  }

  void _onStore() {
    if (!mounted) return;
    final id = _store.activeId;
    if (id != null && !_tabs.contains(id)) _tabs.add(id);
    if (_tabs.length > 8) _tabs.removeAt(0);
    _syncPanes();
    // a rename, pin or folder move changes nothing else, so refresh the tree
    setState(() {});
  }

  /// Keep one pane per sheet: a pane that lost its sheet falls back to another
  /// one (the split closes when there is none), and the focused pane follows
  /// whichever sheet the store was asked to open.
  void _syncPanes() {
    if (_routingOwn) return;
    final ids = _store.sheets.map((s) => s.id).toSet();
    String other(String not) =>
        ids.firstWhere((id) => id != not, orElse: () => '');

    final b = _paneB;
    if (b != null &&
        (!ids.contains(b.sheetId) || b.sheetId == _paneA.sheetId)) {
      final take = other(_paneA.sheetId);
      if (take.isEmpty) {
        _closeSplit();
      } else {
        b.load(take);
      }
    }
    if (!ids.contains(_paneA.sheetId)) {
      final active = _store.activeId ?? '';
      final take = ids.contains(active) && active != _paneB?.sheetId
          ? active
          : other(_paneB?.sheetId ?? '');
      if (take.isEmpty) {
        // the other pane holds the only sheet left: no split is possible
        _closeSplit();
        return;
      }
      _paneA.load(take);
    }

    final id = _store.activeId;
    if (id == null || id == _focused.sheetId) return;
    if (_paneB != null && id == _paneB!.sheetId) {
      _focusB = true;
    } else if (_paneB != null && id == _paneA.sheetId) {
      _focusB = false;
    } else {
      _focused.load(id);
    }
  }

  /// A sidebar click, a tab or a pane menu: open [id] in the focused pane.
  void _activate(String id) {
    final b = _paneB;
    if (b != null && id == b.sheetId) {
      // already in the other pane: move the focus instead of showing it twice
      setState(() => _focusB = true);
    } else {
      if (b != null && id == _paneA.sheetId) setState(() => _focusB = false);
      _focused.load(id);
    }
    _store.select(id);
    if (_split) _saveSettings();
  }

  void _focusPane(PaneState p) {
    if (_paneB == null) return;
    final moved = _focusB != (p == _paneB);
    final reselect = _store.activeId != p.sheetId;
    if (!moved && !reselect) return;
    setState(() => _focusB = p == _paneB);
    if (reselect) _store.select(p.sheetId);
    _saveSettings();
  }

  void _toggleSplit() {
    if (_split) {
      _closeSplit();
      return;
    }
    final other = _store.sheets
        .where((s) => s.id != _paneA.sheetId)
        .firstOrNull;
    if (other != null) {
      setState(() => _paneB = _newPane(other.id));
    } else {
      // one sheet: the split gets a blank one of its own, and the cursor with it
      _routingOwn = true;
      final s = _store.create();
      _routingOwn = false;
      setState(() {
        _paneB = _newPane(s.id);
        _focusB = true;
      });
    }
    _saveSettings();
  }

  void _closeSplit() {
    final b = _paneB;
    if (b == null) return;
    // the right pane's pending debounce must land before the left pane reads it
    b.flush();
    final active = _store.activeId;
    setState(() {
      _paneB = null;
      _focusB = false;
    });
    // the pane leaves this frame first: its controller may only die after
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!b.disposed) b.dispose();
    });
    if (active != null && active != _paneA.sheetId) _paneA.load(active);
    _saveSettings();
  }

  void _closeTab(String id) {
    _tabs.remove(id);
    if (_store.activeId == id && _tabs.isNotEmpty) _store.select(_tabs.last);
    setState(() {});
  }

  void _zoom(double factor) => _setScale((_uiScale * factor).clamp(0.75, 2.5));

  void _setScale(double v) {
    setState(() {
      _uiScale = v.clamp(0.75, 2.5);
      _zoomHud = true;
    });
    _zoomHudTimer?.cancel();
    _zoomHudTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _zoomHud = false);
    });
    _saveSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // paused/detached may be the last callback before the process goes away
    if (state != AppLifecycleState.resumed) _flush();
  }

  /// Write every pending debounce now: a kill, a hidden window or a sheet
  /// switch would otherwise drop it.
  void _flush() {
    for (final p in _livePanes) {
      p.flush();
    }
  }

  Future<void> _fileMenu() async {
    final l = LocaleScope.of(context);
    String t(String k) => T.of(l, k);
    final choice = await showMenu<String>(
      context: _navKey.currentContext!,
      position: const RelativeRect.fromLTRB(60, 48, 0, 0),
      items: [
        PopupMenuItem(value: 'new', child: Text(t('fileNew'))),
        PopupMenuItem(value: 'open', child: Text(t('fileOpen'))),
        PopupMenuItem(value: 'copy', child: Text(t('fileSaveCopy'))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'md', child: Text(t('exportMd'))),
        PopupMenuItem(value: 'csv', child: Text(t('exportCsv'))),
        PopupMenuItem(value: 'txt', child: Text(t('exportTxt'))),
        PopupMenuItem(value: 'print', child: Text(t('filePrint'))),
      ],
    );
    switch (choice) {
      case 'new':
        _store.create();
      case 'open':
        await _openFromFile();
      case 'copy':
        await _saveCopy();
      case 'md' || 'csv' || 'txt':
        await _exportAs(choice!);
      case 'print':
        await _print();
    }
  }

  // ---- file verbs ---------------------------------------------------------

  Future<void> _openFromFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = LocaleScope.of(context);
    try {
      final raw = await FileActions.openDocument();
      if (raw == null) return;
      final parsed = DocumentIo.parse(raw);
      final n = _store.importSheets(parsed.sheets, parsed.folders);
      messenger.showSnackBar(
        SnackBar(content: Text(T.format(l, 'imported', {'n': '$n'}))),
      );
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(T.of(l, 'notTallynote'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open: $e')));
    }
  }

  Future<void> _saveCopy() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = LocaleScope.of(context);
    final now = DateTime.now();
    final name = DocumentIo.fileName(
      _store.active?.title ?? 'tallynote',
      now,
      DocumentIo.fileExtension,
    );
    final ok = await FileActions.saveAs(
      fileName: name,
      content: DocumentIo.libraryJson(_store.sheets, _store.folders, now: now),
      extension: DocumentIo.fileExtension,
    );
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(T.format(l, 'savedAs', {'name': name}))),
      );
    }
  }

  Future<void> _exportAs(String kind) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = LocaleScope.of(context);
    final now = DateTime.now();
    final base = _store.active?.title ?? 'tallynote';
    final engine = _makeEngine();
    final sheets = _store.sheets;
    final (content, ext) = switch (kind) {
      'md' => (DocumentIo.markdown(sheets, engine), 'md'),
      'csv' => (DocumentIo.csv(sheets, engine), 'csv'),
      _ => (DocumentIo.plainText(sheets, engine), 'txt'),
    };
    final name = DocumentIo.fileName(base, now, ext);
    final ok = await FileActions.saveAs(
      fileName: name,
      content: content,
      extension: ext,
    );
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(T.format(l, 'savedAs', {'name': name}))),
      );
    }
  }

  Future<void> _print() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FileActions.printSheets(_store.sheets, _makeEngine());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not print: $e')));
    }
  }

  /// Ctrl/Cmd+S: write now instead of waiting for the debounce.
  void _saveNow() {
    for (final p in _livePanes) {
      p.saveNow();
    }
    setState(() => _savedFlash = true);
    Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _savedFlash = false);
    });
  }

  void _focusSearch() {
    if (!_sidebarOpen) setState(() => _sidebarOpen = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    // last chance: a pending debounce must land before the frame goes away
    _store.removeListener(_onStore);
    for (final p in _livePanes) {
      p.dispose();
    }
    _zoomModifier.dispose();
    _searchFocus.dispose();
    _store.dispose();
    super.dispose();
  }

  void _toggleSidebar() => setState(() => _sidebarOpen = !_sidebarOpen);

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tallynote.dark', _dark);
    await prefs.setBool('tallynote.answers', _answersVisible);
    await prefs.setBool('tallynote.autoRates', _autoRates);
    await prefs.setBool('tallynote.steps', _steps);
    await prefs.setDouble('tallynote.answerWidth', _answerW);
    await prefs.setDouble('tallynote.uiScale', _uiScale);
    if (_locale != null) await prefs.setString('tallynote.locale', _locale!);
    await prefs.setString('tallynote.numberFormat', _numberPreset);
    await prefs.setBool('tallynote.lineNumbers', _lineNumbers);
    await prefs.setBool('tallynote.showTabs', _showTabs);
    await prefs.setBool('tallynote.signColours', _signColours);
    await prefs.setString('tallynote.posColour', _posName);
    await prefs.setString('tallynote.negColour', _negName);
    await prefs.setBool('tallynote.split', _split);
    await prefs.setString('tallynote.splitSheet', _paneB?.sheetId ?? '');
    await prefs.setString(
      'tallynote.splitPrimary',
      _paneB == null ? '' : _paneA.sheetId,
    );
  }

  String get _effectiveLocale {
    final chosen = _locale;
    if (chosen != null) return chosen;
    final sys = WidgetsBinding.instance.platformDispatcher.locale;
    if (sys.languageCode == 'zh') {
      return sys.scriptCode == 'Hans' || sys.countryCode == 'CN'
          ? 'zh_Hans'
          : 'zh_Hant';
    }
    return 'en';
  }

  Locale get _materialLocale => switch (_effectiveLocale) {
    'zh_Hant' => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    ),
    'zh_Hans' => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
    ),
    _ => const Locale('en'),
  };

  void _format(String open, String close) => _focused.format(open, close);

  /// Split off: today's single editor. Split on: the two panes side by side
  /// when each one still gets the 340px a pane needs, stacked when it does not
  /// (a phone, or a tablet with the sidebar open).
  ///
  /// [width] is the editor area, not the window: the sidebar takes 250px of it.
  Widget _panesView(double width) {
    final b = _paneB;
    if (b == null) {
      return _pane(_paneA, focused: true, showTitle: false);
    }
    final top = _pane(_paneA, focused: !_focusB, showTitle: true);
    final bottom = _pane(
      b,
      focused: _focusB,
      showTitle: true,
      onUnsplit: _closeSplit,
    );
    final each = (width - 1) / 2; // one pane's own width, less the divider
    final side = width >= 1000 || (width >= 700 && each >= 340);
    if (!side) {
      return Column(
        key: const ValueKey('split-column'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: top),
          Divider(height: 1, color: Palette.hairline(_dark)),
          Expanded(child: bottom),
        ],
      );
    }
    return Row(
      key: const ValueKey('split-row'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: top),
        VerticalDivider(width: 1, color: Palette.hairline(_dark)),
        Expanded(child: bottom),
      ],
    );
  }

  Widget _pane(
    PaneState p, {
    required bool focused,
    required bool showTitle,
    VoidCallback? onUnsplit,
  }) => EditorPane(
    pane: p,
    dark: _dark,
    focused: focused,
    showTitle: showTitle,
    otherSheetId: (p == _paneA ? _paneB : _paneA)?.sheetId,
    answersVisible: _answersVisible,
    showSteps: _steps,
    showLineNumbers: _lineNumbers,
    signColours: _signColours,
    positiveColour: _posName.isEmpty ? null : Fmt.colours[_posName],
    negativeColour: _negName.isEmpty ? null : Fmt.colours[_negName],
    wheelBlocked: _zoomModifier,
    onUnsplit: onUnsplit,
    onFocus: () => _focusPane(p),
    onPickSheet: _activate,
    onAnswerWidth: (w) {
      _answerW = w;
      _saveSettings();
    },
  );

  @override
  Widget build(BuildContext context) {
    for (final p in _livePanes) {
      p.controller.dark = _dark;
      // each line only sees the names defined above it
      p.applyLabels();
    }
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final theme = buildTheme(_dark);

    final sidebar = Sidebar(
      store: _store,
      dark: _dark,
      wheelBlocked: _zoomModifier,
      searchFocus: _searchFocus,
      onClose: wide ? _toggleSidebar : () => Navigator.of(context).maybePop(),
    );

    return MaterialApp(
      title: 'Tallynote',
      debugShowCheckedModeBanner: false,
      locale: _materialLocale,
      supportedLocales: const [
        Locale('en'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final s = _uiScale;
        if ((s - 1).abs() < 0.01) {
          return LocaleScope(locale: _effectiveLocale, child: child);
        }
        final mq = MediaQuery.of(context);
        final logical = mq.size / s;
        // OverflowBox pins the child to the reduced logical size; the transform
        // then paints it back to exactly one screen, so nothing spills out and
        // no gap is left behind.
        return LocaleScope(
          locale: _effectiveLocale,
          child: ColoredBox(
            color: Palette.bg(_dark),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: logical.width,
                maxWidth: logical.width,
                minHeight: logical.height,
                maxHeight: logical.height,
                child: Transform.scale(
                  key: const ValueKey('ui-zoom'),
                  scale: s,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: logical.width,
                    height: logical.height,
                    child: MediaQuery(
                      data: mq.copyWith(
                        size: logical,
                        padding: mq.padding / s,
                        viewPadding: mq.viewPadding / s,
                        viewInsets: mq.viewInsets / s,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      navigatorKey: _navKey,
      theme: theme,
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
              _zoom(1.25),
          const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
              _zoom(1.25),
          const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
              _zoom(0.8),
          const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
              _zoom(0.8),
          const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () {
            setState(() => _uiScale = 1.0);
            _saveSettings();
          },
          const SingleActivator(LogicalKeyboardKey.digit0, control: true): () {
            setState(() => _uiScale = 1.0);
            _saveSettings();
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveNow,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _saveNow,
          const SingleActivator(
            LogicalKeyboardKey.keyD,
            meta: true,
            shift: true,
          ): () {
            final id = _store.activeId;
            if (id != null) _store.duplicate(id);
          },
          const SingleActivator(
            LogicalKeyboardKey.keyD,
            control: true,
            shift: true,
          ): () {
            final id = _store.activeId;
            if (id != null) _store.duplicate(id);
          },
          // rich-text shortcuts, the same keys as Word / Google Docs
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
              _format('**', '**'),
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
              _format('**', '**'),
          const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
              _format('_', '_'),
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
              _format('_', '_'),
          const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () =>
              _format('__', '__'),
          const SingleActivator(LogicalKeyboardKey.keyU, control: true): () =>
              _format('__', '__'),
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          ): () =>
              _format('~~', '~~'),
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () =>
              _format('~~', '~~'),
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _focusSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _focusSearch,
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
            final id = _store.activeId;
            if (id != null) _closeTab(id);
          },
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
            final id = _store.activeId;
            if (id != null) _closeTab(id);
          },
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
              _store.create(),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              _store.create(),
          const SingleActivator(LogicalKeyboardKey.backslash, meta: true):
              _toggleSidebar,
          const SingleActivator(LogicalKeyboardKey.backslash, control: true):
              _toggleSidebar,
          const SingleActivator(
            LogicalKeyboardKey.backslash,
            meta: true,
            shift: true,
          ): _toggleSplit,
          const SingleActivator(
            LogicalKeyboardKey.backslash,
            control: true,
            shift: true,
          ): _toggleSplit,
          const SingleActivator(
            LogicalKeyboardKey.keyA,
            meta: true,
            shift: true,
          ): () {
            setState(() => _answersVisible = !_answersVisible);
            _saveSettings();
          },
          const SingleActivator(
            LogicalKeyboardKey.keyA,
            control: true,
            shift: true,
          ): () {
            setState(() => _answersVisible = !_answersVisible);
            _saveSettings();
          },
        },
        child: Focus(
          autofocus: true,
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: Scaffold(
              key: _scaffoldKey,
              drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
              body: SafeArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide && _sidebarOpen) ...[
                      sidebar,
                      VerticalDivider(width: 1, color: Palette.hairline(_dark)),
                    ],
                    Expanded(
                      child: Column(
                        children: [
                          _Header(
                            dark: _dark,
                            sidebarOpen: _sidebarOpen && wide,
                            showMenu: !(wide && _sidebarOpen),
                            split: _split,
                            onSplit: _toggleSplit,
                            onMenu: wide
                                ? _toggleSidebar
                                : () => _scaffoldKey.currentState?.openDrawer(),
                            onFile: _fileMenu,
                            onSettings: () => showSettingsSheet(
                              context: _navKey.currentContext!,
                              dark: _dark,
                              answersVisible: _answersVisible,
                              autoRates: _autoRates,
                              steps: _steps,
                              signColours: _signColours,
                              lineNumbers: _lineNumbers,
                              showTabs: _showTabs,
                              uiScale: _uiScale,
                              locale: _locale ?? _effectiveLocale,
                              numberPreset: _numberPreset,
                              onLocale: (v) {
                                setState(() => _locale = v);
                                _saveSettings();
                              },
                              onNumberPreset: (v) {
                                setState(() => _numberPreset = v);
                                for (final p in _livePanes) {
                                  p.rebuildEngine();
                                }
                                _saveSettings();
                              },
                              posName: _posName,
                              negName: _negName,
                              onAnswers: (v) {
                                setState(() => _answersVisible = v);
                                _saveSettings();
                              },
                              onTheme: (v) {
                                setState(() => _dark = v);
                                _saveSettings();
                              },
                              onAutoRates: (v) {
                                setState(() => _autoRates = v);
                                _saveSettings();
                              },
                              onSteps: (v) {
                                setState(() => _steps = v);
                                _saveSettings();
                              },
                              onSignColours: (v) {
                                setState(() => _signColours = v);
                                _saveSettings();
                              },
                              onPosColour: (name) {
                                setState(() => _posName = name);
                                _saveSettings();
                              },
                              onNegColour: (name) {
                                setState(() => _negName = name);
                                _saveSettings();
                              },
                              onLineNumbers: (v) {
                                setState(() => _lineNumbers = v);
                                _saveSettings();
                              },
                              onShowTabs: (v) {
                                setState(() => _showTabs = v);
                                _saveSettings();
                              },
                              onUiScale: (v) {
                                setState(() => _uiScale = v);
                                _saveSettings();
                              },
                              onRefreshRates: () async {
                                final ok = await Rates.refresh();
                                if (!mounted) return false;
                                for (final p in _livePanes) {
                                  p.rebuildEngine();
                                }
                                return ok;
                              },
                            ),
                          ),
                          Divider(height: 1, color: Palette.hairline(_dark)),
                          if (_showTabs && _tabs.length > 1)
                            _TabBar(
                              dark: _dark,
                              tabs: _tabs,
                              activeId: _store.activeId,
                              titleOf: (id) {
                                final s = _store.sheets
                                    .where((x) => x.id == id)
                                    .firstOrNull;
                                return s == null || s.title.isEmpty
                                    ? 'Untitled'
                                    : s.title;
                              },
                              onSelect: _store.select,
                              onClose: _closeTab,
                            ),
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  // the split's breakpoint is about the room
                                  // the editor has, so measure that, not the
                                  // window: the sidebar eats 250px of it
                                  child: LayoutBuilder(
                                    builder: (context, box) =>
                                        _panesView(box.maxWidth),
                                  ),
                                ),
                                if (_zoomHud)
                                  Positioned(
                                    right: 18,
                                    bottom: 18,
                                    child: _ZoomHud(
                                      dark: _dark,
                                      scale: _uiScale,
                                      onMinus: () => _zoom(1 / 1.1),
                                      onPlus: () => _zoom(1.1),
                                      onReset: () => _setScale(1.0),
                                    ),
                                  ),
                                if (_focused.hasSelection)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 14,
                                    child: Center(
                                      child: _FormatBar(
                                        dark: _dark,
                                        onFormat: _format,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _StatusBar(
                            dark: _dark,
                            dirty: _focused.dirty,
                            justSaved: _savedFlash,
                            saveFailed: _store.saveFailed,
                            savedAt: _focused.lastSaved,
                            lines: _focused.controller.text.split('\n').length,
                            answers: _focused.results
                                .where((r) => r.display != null)
                                .length,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool dark;
  final bool sidebarOpen;

  /// The sidebar carries its own collapse control, so the header only shows a
  /// menu button when the sidebar is actually hidden.
  final bool showMenu;
  final bool split;
  final VoidCallback onMenu;
  final VoidCallback onSplit;
  final VoidCallback onFile;
  final VoidCallback onSettings;

  const _Header({
    required this.dark,
    required this.sidebarOpen,
    required this.showMenu,
    required this.split,
    required this.onMenu,
    required this.onSplit,
    required this.onFile,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (showMenu)
              IconButton(
                iconSize: 18,
                tooltip: '${LocaleScope.t(context, 'sheets')}  ⌘\\',
                onPressed: onMenu,
                icon: Icon(Icons.menu, color: Palette.faint(dark)),
              ),
            const Spacer(),
            _IconAction(
              icon: Icons.folder_open_outlined,
              tooltip: LocaleScope.t(context, 'file'),
              dark: dark,
              onTap: onFile,
            ),
            _IconAction(
              icon: Icons.vertical_split,
              tooltip: '${LocaleScope.t(context, 'split')}  ⌘⇧\\',
              dark: dark,
              active: split,
              onTap: onSplit,
            ),
            _IconAction(
              icon: Icons.tune,
              tooltip: LocaleScope.t(context, 'settings'),
              dark: dark,
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool dark;

  /// On while the thing it toggles is on.
  final bool active;
  final VoidCallback onTap;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.dark,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 17,
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: active ? Palette.fg(dark) : Palette.faint(dark)),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final bool dark;
  final int lines;
  final int answers;
  final bool dirty;
  final bool justSaved;
  final bool saveFailed;
  final DateTime? savedAt;

  const _StatusBar({
    required this.dark,
    required this.lines,
    required this.answers,
    required this.dirty,
    required this.justSaved,
    required this.saveFailed,
    required this.savedAt,
  });

  /// "editing…" while the debounce is pending, else the last save time.
  String _saveLabelFor(String locale) {
    if (saveFailed) return T.of(locale, 'saveFailed');
    if (dirty) return T.of(locale, 'editing');
    if (justSaved) return T.of(locale, 'justSaved');
    final at = savedAt;
    if (at == null) return '';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    final sameDay =
        at.year == DateTime.now().year &&
        at.month == DateTime.now().month &&
        at.day == DateTime.now().day;
    final time = '$hh:$mm';
    return sameDay
        ? T.format(locale, 'savedAt', {'time': time})
        : T.format(locale, 'savedOn', {
            'date': '${at.day}/${at.month}',
            'time': time,
          });
  }

  @override
  Widget build(BuildContext context) {
    final locale = LocaleScope.of(context);
    final rateDate = Rates.updatedDate ?? T.of(locale, 'ratesBuiltIn');
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Palette.hairline(dark))),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              T.format(locale, 'linesAnswers', {
                'lines': '$lines',
                'answers': '$answers',
              }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Palette.faint(dark)),
            ),
          ),
          const SizedBox(width: 12),
          if (_saveLabelFor(locale).isNotEmpty) ...[
            Text(
              _saveLabelFor(locale),
              style: TextStyle(
                fontSize: 11,
                color: justSaved ? Palette.positive(dark) : Palette.faint(dark),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Text(
              T.format(locale, 'rates', {'date': rateDate}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: Palette.faint(dark)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatBar extends StatelessWidget {
  final bool dark;
  final void Function(String open, String close) onFormat;

  const _FormatBar({required this.dark, required this.onFormat});

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, TextStyle style, String open, String close) =>
        Pressable(
          onTap: () => onFormat(open, close),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Text(label, style: style.copyWith(color: Palette.fg(dark))),
          ),
        );

    final base = TextStyle(fontSize: 13, fontFamily: monoFamily);
    // a floating card: showing it must not reflow the text above
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: Palette.bg(dark),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Palette.hairline(dark)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: [
            const SizedBox(width: 8),
            btn('B', base.copyWith(fontWeight: FontWeight.w700), '**', '**'),
            btn('I', base.copyWith(fontStyle: FontStyle.italic), '_', '_'),
            btn(
              'S',
              base.copyWith(decoration: TextDecoration.lineThrough),
              '~~',
              '~~',
            ),
            btn(
              'U',
              base.copyWith(decoration: TextDecoration.underline),
              '__',
              '__',
            ),
            const SizedBox(width: 6),
            for (final entry in Fmt.colours.entries)
              Pressable(
                onTap: () => onFormat('{${entry.key}}', '{/}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 9,
                  ),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final bool dark;
  final List<String> tabs;
  final String? activeId;
  final String Function(String id) titleOf;
  final void Function(String id) onSelect;
  final void Function(String id) onClose;

  const _TabBar({
    required this.dark,
    required this.tabs,
    required this.activeId,
    required this.titleOf,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.hairline(dark))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final id in tabs)
            Pressable(
              onTap: () => onSelect(id),
              padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
              child: Row(
                children: [
                  Text(
                    titleOf(id),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: id == activeId
                          ? Palette.fg(dark)
                          : Palette.faint(dark),
                    ),
                  ),
                  Pressable(
                    onTap: () => onClose(id),
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close,
                      size: 11,
                      color: Palette.faint(dark),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomHud extends StatelessWidget {
  final bool dark;
  final double scale;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onReset;

  const _ZoomHud({
    required this.dark,
    required this.scale,
    required this.onMinus,
    required this.onPlus,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final locale = LocaleScope.of(context);
    Widget button(IconData icon, String tip, VoidCallback tap) => Pressable(
      onTap: tap,
      padding: const EdgeInsets.all(7),
      child: Tooltip(
        message: tip,
        child: Icon(icon, size: 15, color: Palette.fg(dark)),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Palette.bg(dark),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Palette.hairline(dark)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(Icons.remove, '${T.of(locale, 'zoomOut')}  ⌘−', onMinus),
            SizedBox(
              width: 46,
              child: Text(
                '${(scale * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontFeatures: const [],
                  color: Palette.fg(dark),
                ),
              ),
            ),
            button(Icons.add, '${T.of(locale, 'zoomIn')}  ⌘=', onPlus),
            Container(width: 1, height: 16, color: Palette.hairline(dark)),
            button(
              Icons.restart_alt,
              '${T.of(locale, 'zoomReset')}  ⌘0',
              onReset,
            ),
          ],
        ),
      ),
    );
  }
}
